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


    /// Check if the app has Accessibility permission (needed for CGEvent posting / auto-paste).
    /// Uses `AXIsProcessTrustedWithOptions` as primary check, with a runtime CGEvent fallback
    /// to handle cases where the TCC database entry is stale (e.g. after ad-hoc rebuild).
    static var isAccessibilityGranted: Bool {
        if AXIsProcessTrustedWithOptions(accessibilityStatusOptions) {
            return true
        }
        return canPostCGEvents()
    }

    /// Runtime test: attempt to create a CGEvent to verify we actually have accessibility access.
    /// This catches cases where TCC reports false but the process actually has permission,
    /// or where the TCC entry is stale after a code signature change.
    private static func canPostCGEvents() -> Bool {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0xFFFF, keyDown: true) else {
            return false
        }
        return event.type == .keyDown
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
