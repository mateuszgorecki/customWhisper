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

    @AppStorage(AppConstants.DefaultsKey.lmStudioBaseURL)
    private var lmStudioBaseURL = AppConstants.Meeting.defaultLMStudioBaseURL
    @AppStorage(AppConstants.DefaultsKey.correctionModel)
    private var correctionModel = AppConstants.Meeting.defaultCorrectionModel
    @AppStorage(AppConstants.DefaultsKey.autoCorrectAfterTranscription)
    private var autoCorrectAfterTranscription = false
    @AppStorage(AppConstants.DefaultsKey.meetingOutputFolder)
    private var meetingOutputFolder = ""

    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelsError: String?

    @State private var isRedownloading = false
    @State private var microphoneStatus: MicrophonePermissionStatus = Permissions.microphonePermissionStatus
    @State private var accessibilityPermissionState: AccessibilityPermissionState = Permissions.accessibilityPermissionSnapshot().state
    @State private var shouldAutoRelaunchOnPermissionGrant = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                modelSection
                shortcutsSection
                behaviorSection
                meetingSection
                systemSection
                permissionsSection
            }
            .padding(24)
        }
        .onAppear {
            refreshPermissionStates()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
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
                    Text("Push to Talk")
                        .frame(width: 150, alignment: .leading)
                    KeyboardShortcuts.Recorder(for: .pushToTalk)
                }

                HStack {
                    Text("Cancel Recording")
                        .frame(width: 150, alignment: .leading)
                    KeyboardShortcuts.Recorder(for: .cancelRecording)
                }

                Text("Toggle Recording: press once to start, press again to stop. Push to Talk: hold to record, release to stop.")
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

    // MARK: - Meeting Section

    @ViewBuilder
    private var meetingSection: some View {
        SettingsSection(title: "Meeting Transcription", icon: "person.wave.2") {
            VStack(alignment: .leading, spacing: 12) {
                // Output folder
                VStack(alignment: .leading, spacing: 4) {
                    Text("Output folder")
                        .font(.subheadline.weight(.medium))
                    HStack {
                        Text(meetingOutputFolder.isEmpty ? "Not set — files won't be written to disk" : meetingOutputFolder)
                            .font(.caption)
                            .foregroundStyle(meetingOutputFolder.isEmpty ? .secondary : .primary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if !meetingOutputFolder.isEmpty {
                            Button("Clear") { meetingOutputFolder = "" }
                                .buttonStyle(.borderless)
                                .controlSize(.small)
                        }
                        Button("Choose…") { chooseOutputFolder() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Text("Transcripts are saved as <name>.txt and <name>.corrected.txt here. History is kept in the app regardless.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                // LM Studio correction
                VStack(alignment: .leading, spacing: 4) {
                    Text("Local correction (LM Studio)")
                        .font(.subheadline.weight(.medium))

                    TextField("LM Studio URL", text: $lmStudioBaseURL)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Picker("Model", selection: $correctionModel) {
                            if !availableModels.contains(correctionModel) {
                                Text(correctionModel).tag(correctionModel)
                            }
                            ForEach(availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()

                        Button {
                            fetchModels()
                        } label: {
                            if isLoadingModels {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isLoadingModels)
                    }

                    if let modelsError {
                        Text(modelsError)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    Text("Fixes spelling, punctuation, and mis-heard words without changing meaning. Requires LM Studio running with a model loaded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                Toggle("Auto-correct after transcription", isOn: $autoCorrectAfterTranscription)
                Text("Run the correction model automatically once a meeting is transcribed.")
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
                    if accessibilityPermissionState == .granted {
                        Label("Accessibility: Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if accessibilityPermissionState == .stale {
                        Label("Accessibility: Stale", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        Spacer()

                        Button("Reset & Re-grant") {
                            shouldAutoRelaunchOnPermissionGrant = true
                            Permissions.resetAccessibilityPermission()
                            Permissions.invalidateAccessibilityCache()
                            Permissions.requestAccessibility()
                            Permissions.openAccessibilitySettings()
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

                if accessibilityPermissionState == .stale {
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

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            meetingOutputFolder = url.path
        }
    }

    private func fetchModels() {
        isLoadingModels = true
        modelsError = nil
        let service = TranscriptCorrectionService(baseURL: lmStudioBaseURL, model: correctionModel)
        Task {
            do {
                let models = try await service.availableModels()
                await MainActor.run {
                    availableModels = models
                    isLoadingModels = false
                }
            } catch {
                await MainActor.run {
                    modelsError = error.localizedDescription
                    isLoadingModels = false
                }
            }
        }
    }

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

    private func refreshPermissionStates(forceRefreshAccessibility: Bool = false) {
        microphoneStatus = Permissions.microphonePermissionStatus
        accessibilityPermissionState = Permissions.accessibilityPermissionSnapshot(
            forceRefreshRuntime: forceRefreshAccessibility
        ).state
    }

    private func handleReturnFromSystemSettings() {
        let previousMicrophoneStatus = microphoneStatus
        let previousAccessibilityState = accessibilityPermissionState
        refreshPermissionStates(forceRefreshAccessibility: true)

        guard shouldAutoRelaunchOnPermissionGrant else { return }
        let microphoneGrantedNow = previousMicrophoneStatus != .authorized && microphoneStatus == .authorized
        let accessibilityGrantedNow = previousAccessibilityState != .granted && accessibilityPermissionState == .granted

        if microphoneGrantedNow || accessibilityGrantedNow {
            shouldAutoRelaunchOnPermissionGrant = false
            Permissions.relaunchApplication()
            return
        }

        shouldAutoRelaunchOnPermissionGrant = false
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
