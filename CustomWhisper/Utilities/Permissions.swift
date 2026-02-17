import ApplicationServices
import AppKit
import AVFoundation
import CoreGraphics

enum MicrophonePermissionStatus {
    case authorized
    case denied
    case restricted
    case notDetermined
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

    /// Check if the app **actually** has Accessibility permission by attempting to create a
    /// `CGEventTap`.  This is the kernel-level check that correctly rejects stale TCC entries
    /// (e.g. after an ad-hoc rebuild changes the code signature).
    /// The result is cached; call `invalidateAccessibilityCache()` to force a re-check.
    static var isAccessibilityGranted: Bool {
        if let cached = cachedAccessibility { return cached }
        let result = canCreateEventTap()
        cachedAccessibility = result
        return result
    }

    /// `true` when the TCC database reports the permission as granted but the runtime check
    /// disagrees -- typically caused by a stale entry after rebuild.
    static var isAccessibilityStale: Bool {
        let tccGranted = AXIsProcessTrustedWithOptions(accessibilityStatusOptions)
        return tccGranted && !isAccessibilityGranted
    }

    /// Runtime test: attempt to create a passive, listen-only `CGEventTap`.
    /// Creating a tap requires actual accessibility permission at the kernel level;
    /// it returns `nil` when the process is not trusted, regardless of TCC cache state.
    /// The tap is never added to a run loop -- we only test `!= nil` and let it deallocate.
    private static func canCreateEventTap() -> Bool {
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { _, _, event, _ in Unmanaged.passUnretained(event) },
            userInfo: nil
        )
        return tap != nil
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
