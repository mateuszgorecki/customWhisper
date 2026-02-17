import ApplicationServices
import AppKit
import AVFoundation

enum MicrophonePermissionStatus {
    case authorized
    case denied
    case restricted
    case notDetermined
}

enum AccessibilityPermissionState {
    case granted
    case stale
    case notGranted
}

struct AccessibilityPermissionSnapshot {
    let tccGranted: Bool
    let runtimeGranted: Bool

    var state: AccessibilityPermissionState {
        if runtimeGranted { return .granted }
        if tccGranted { return .stale }
        return .notGranted
    }
}

enum Permissions {
    private static var accessibilityPromptKey: String {
        kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    }

    private static var accessibilityStatusOptions: CFDictionary {
        [accessibilityPromptKey: false] as CFDictionary
    }

    @MainActor
    private static func requestRecordPermissionViaAudioApplication() async -> Bool? {
        guard #available(macOS 14.0, *) else { return nil }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        @unknown default:
            return false
        }
    }


    // MARK: - Accessibility (cached runtime check)

    private static var cachedAccessibility: Bool?

    /// Invalidate the cached accessibility result so the next access re-checks at the kernel level.
    /// Call this when the app is re-activated (returning from System Settings) or on manual refresh.
    static func invalidateAccessibilityCache() {
        cachedAccessibility = nil
    }

    /// Runtime accessibility check with optional cache bypass.
    private static func runtimeAccessibilityGranted(forceRefresh: Bool) -> Bool {
        if !forceRefresh, let cached = cachedAccessibility {
            return cached
        }

        let result = canAccessAccessibilityAPI()
        cachedAccessibility = result
        return result
    }

    /// Build a single snapshot so UI and behavior use one coherent source of truth.
    static func accessibilityPermissionSnapshot(forceRefreshRuntime: Bool = false) -> AccessibilityPermissionSnapshot {
        let tccGranted = AXIsProcessTrustedWithOptions(accessibilityStatusOptions)
        let runtimeGranted = runtimeAccessibilityGranted(forceRefresh: forceRefreshRuntime)
        return AccessibilityPermissionSnapshot(tccGranted: tccGranted, runtimeGranted: runtimeGranted)
    }

    /// Check if the app **actually** has Accessibility permission by probing AX runtime APIs.
    /// This catches stale TCC entries where database state and effective runtime access disagree.
    /// The result is cached; call `invalidateAccessibilityCache()` to force a re-check.
    static var isAccessibilityGranted: Bool {
        accessibilityPermissionSnapshot().runtimeGranted
    }

    /// `true` when the TCC database reports the permission as granted but the runtime check
    /// disagrees -- typically caused by a stale entry after rebuild.
    static var isAccessibilityStale: Bool {
        accessibilityPermissionSnapshot().state == .stale
    }

    /// Runtime test: query system-wide AX attributes.
    /// Without Accessibility permission, AX APIs return `.apiDisabled`.
    /// With permission, they typically return `.success` or `.noValue` depending on UI context.
    private static func canAccessAccessibilityAPI() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        )
        if appResult == .success || appResult == .noValue {
            return true
        }

        var focusedElement: CFTypeRef?
        let elementResult = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )
        return elementResult == .success || elementResult == .noValue
    }

    /// Clear the stale TCC entry for this app's Accessibility permission using `tccutil`.
    /// After calling this the user must re-grant the permission in System Settings.
    static func resetAccessibilityPermission() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.customwhisper.CustomWhisper"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Accessibility", bundleID]
        try? process.run()
        process.waitUntilExit()
    }

    /// Prompt the user to grant Accessibility permission.
    /// Opens System Settings > Privacy & Security > Accessibility with this app highlighted.
    static func requestAccessibility() {
        let options = [accessibilityPromptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Open System Settings screen for Accessibility permissions.
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Check if the app has microphone permission.
    static func checkMicrophonePermission() async -> Bool {
        if let granted = await requestRecordPermissionViaAudioApplication() {
            return granted
        }

        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        default:
            return false
        }
    }

    static var microphonePermissionStatus: MicrophonePermissionStatus {
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return .authorized
            case .denied:
                return .denied
            case .undetermined:
                return .notDetermined
            @unknown default:
                return .restricted
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .restricted
        }
    }

    /// Open System Settings screen for Microphone permissions.
    static func openMicrophoneSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    /// Relaunch app so newly granted permissions are applied immediately.
    /// Spawns a background shell that waits for the current process to exit, then reopens the app.
    static func relaunchApplication() {
        let appPath = Bundle.main.bundleURL.path
        let pid = ProcessInfo.processInfo.processIdentifier

        let script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.1; done; open \"\(appPath)\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]

        do {
            try process.run()
        } catch {
            print("Failed to schedule relaunch: \(error.localizedDescription)")
        }

        DispatchQueue.main.async {
            NSApp.terminate(nil)
        }
    }
}
