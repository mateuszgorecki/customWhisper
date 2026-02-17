import SwiftUI
import KeyboardShortcuts
import ServiceManagement
import AppKit

struct SettingsView: View {
    @Environment(AppStateMachine.self) private var stateMachine

    @AppStorage("modelVersion") private var modelVersion = "v3"
    @AppStorage("autoPaste") private var autoPaste = true
    @AppStorage("saveHistory") private var saveHistory = true
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    @State private var isRedownloading = false
    @State private var microphoneStatus: MicrophonePermissionStatus = Permissions.microphonePermissionStatus
    @State private var accessibilityGranted: Bool = Permissions.isAccessibilityGranted
    @State private var accessibilityStale: Bool = Permissions.isAccessibilityStale
    @State private var shouldAutoRelaunchOnPermissionGrant = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                modelSection
                shortcutsSection
                behaviorSection
                systemSection
                permissionsSection
            }
            .padding(24)
        }
        .onAppear {
            refreshPermissionStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Permissions.invalidateAccessibilityCache()
            handleReturnFromSystemSettings()
        }
    }

    // MARK: - Model Section

    @ViewBuilder
    private var modelSection: some View {
        SettingsSection(title: "Transcription Model", icon: "brain") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Model Version", selection: $modelVersion) {
                    ForEach(AppConstants.ModelVersion.allCases) { version in
                        Text(version.displayName).tag(version.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: modelVersion) { _, newValue in
                    Task {
                        let version = AppConstants.ModelVersion(rawValue: newValue) ?? .v3
                        try? await stateMachine.transcriptionService.loadModel(version: version)
                    }
                }

                if let version = AppConstants.ModelVersion(rawValue: modelVersion) {
                    Text(version.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if stateMachine.transcriptionService.isModelLoaded {
                        Label("Model loaded", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else if stateMachine.transcriptionService.isDownloading {
                        ProgressView(value: stateMachine.transcriptionService.downloadProgress)
                            .frame(maxWidth: 200)
                        Text("Downloading...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Model not loaded", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    Button("Re-download Model") {
                        redownloadModel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRedownloading)
                }
            }
        }
    }

    // MARK: - Shortcuts Section

    @ViewBuilder
    private var shortcutsSection: some View {
        SettingsSection(title: "Keyboard Shortcuts", icon: "keyboard") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Toggle Recording")
                        .frame(width: 150, alignment: .leading)
                    KeyboardShortcuts.Recorder(for: .toggleRecording)
                }

                HStack {
                    Text("Cancel Recording")
                        .frame(width: 150, alignment: .leading)
                    KeyboardShortcuts.Recorder(for: .cancelRecording)
                }

                Text("Use the shortcut from any app to start/stop dictation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Behavior Section

    @ViewBuilder
    private var behaviorSection: some View {
        SettingsSection(title: "Behavior", icon: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Auto-paste after transcription", isOn: $autoPaste)
                Text("When enabled, transcribed text is automatically pasted at the cursor position. When disabled, text is copied to clipboard.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                Toggle("Save transcription history", isOn: $saveHistory)
                Text("Keep a record of all transcriptions for later review.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - System Section

    @ViewBuilder
    private var systemSection: some View {
        SettingsSection(title: "System", icon: "gearshape.2") {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    setLaunchAtLogin(newValue)
                }
        }
    }

    // MARK: - Permissions Section

    @ViewBuilder
    private var permissionsSection: some View {
        SettingsSection(title: "Permissions", icon: "lock.shield") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    switch microphoneStatus {
                    case .authorized:
                        Label("Microphone: Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    case .notDetermined:
                        Label("Microphone: Not Requested", systemImage: "questionmark.circle.fill")
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("Request Access") {
                            shouldAutoRelaunchOnPermissionGrant = true
                            Task {
                                _ = await Permissions.checkMicrophonePermission()
                                refreshPermissionStates()
                                if microphoneStatus == .authorized {
                                    Permissions.relaunchApplication()
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    case .denied, .restricted:
                        Label("Microphone: Not Granted", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Open Microphone Settings") {
                            shouldAutoRelaunchOnPermissionGrant = true
                            Permissions.openMicrophoneSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                HStack {
                    if accessibilityGranted {
                        Label("Accessibility: Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if accessibilityStale {
                        Label("Accessibility: Stale", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        Spacer()

                        Button("Reset & Re-grant") {
                            shouldAutoRelaunchOnPermissionGrant = true
                            Permissions.resetAccessibilityPermission()
                            Permissions.invalidateAccessibilityCache()
                            Permissions.requestAccessibility()
                            Permissions.relaunchApplication()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Label("Accessibility: Not Granted", systemImage: "xmark.circle.fill")
                            .foregroundStyle(.red)

                        Spacer()

                        Button("Grant Access") {
                            shouldAutoRelaunchOnPermissionGrant = true
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                if accessibilityStale {
                    Text("Permission was invalidated by a rebuild. Click \"Reset & Re-grant\" to clear the stale entry and re-authorize.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if shouldAutoRelaunchOnPermissionGrant {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise.circle")
                        Text("App will restart automatically after permission is granted.")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Divider()

                Text("Accessibility permission is required to auto-paste text into other apps.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Microphone permission is required to record audio for transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack {
                    Text("If permissions seem stuck, try restarting the app:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Relaunch App") {
                        Permissions.relaunchApplication()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text("App: \(Bundle.main.bundlePath)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Helpers

    private func redownloadModel() {
        isRedownloading = true
        stateMachine.transcriptionService.cleanup()

        Task {
            let version = AppConstants.ModelVersion(rawValue: modelVersion) ?? .v3
            try? await stateMachine.transcriptionService.loadModel(version: version)
            isRedownloading = false
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
        }
    }

    private func refreshPermissionStates() {
        microphoneStatus = Permissions.microphonePermissionStatus
        accessibilityGranted = Permissions.isAccessibilityGranted
        accessibilityStale = Permissions.isAccessibilityStale
    }

    private func handleReturnFromSystemSettings() {
        let previousMicrophoneStatus = microphoneStatus
        let previousAccessibilityGranted = accessibilityGranted
        refreshPermissionStates()

        guard shouldAutoRelaunchOnPermissionGrant else { return }
        let microphoneGrantedNow = previousMicrophoneStatus != .authorized && microphoneStatus == .authorized
        let accessibilityGrantedNow = !previousAccessibilityGranted && accessibilityGranted

        if microphoneGrantedNow || accessibilityGrantedNow {
            Permissions.relaunchApplication()
        }
    }
}

// MARK: - Reusable Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)

            content()
                .padding(16)
                .background {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.background)
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                }
        }
    }
}
