import AppKit
import Foundation
import Observation
import KeyboardShortcuts
import SwiftData

/// Central coordinator that manages the dictation pipeline state and
/// connects AudioRecorder, TranscriptionService, and TextPaster.
@Observable
final class AppStateMachine {

    // MARK: - State

    private(set) var state: AppState = .idle
    private(set) var lastTranscription: String?

    // MARK: - Services

    let recorder = AudioRecorder()
    let transcriptionService = TranscriptionService()

    // MARK: - Settings (read from UserDefaults)

    var autoPaste: Bool {
        UserDefaults.standard.bool(forKey: "autoPaste")
    }

    var saveHistory: Bool {
        UserDefaults.standard.bool(forKey: "saveHistory")
    }

    // MARK: - SwiftData

    var modelContext: ModelContext?

    // MARK: - Overlay

    var overlayController: RecordingOverlayController?

    // MARK: - Private

    private var overlayUpdateTimer: Timer?

    // MARK: - Init

    init() {
        UserDefaults.standard.register(defaults: [
            "autoPaste": true,
            "saveHistory": true,
            "modelVersion": "v3",
        ])

        setupShortcuts()
    }

    // MARK: - Actions

    /// Toggle between idle and recording states, or stop recording if currently recording.
    func toggle() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            stopRecordingAndTranscribe()
        case .processing:
            break
        case .error:
            state = .idle
        }
    }

    /// Cancel the current recording without transcribing.
    func cancel() {
        guard state == .recording else { return }
        recorder.cancelRecording()
        stopOverlayUpdates()
        state = .idle
        overlayController?.hide()
    }

    /// Load the transcription model based on the user's settings.
    func loadModelFromSettings() async {
        let versionString = UserDefaults.standard.string(forKey: "modelVersion") ?? "v3"
        let version = AppConstants.ModelVersion(rawValue: versionString) ?? .v3

        do {
            try await transcriptionService.loadModel(version: version)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    // MARK: - Private - Shortcuts

    private func setupShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .toggleRecording) { [weak self] in
            self?.toggle()
        }

        KeyboardShortcuts.onKeyUp(for: .cancelRecording) { [weak self] in
            self?.cancel()
        }
    }

    // MARK: - Private - Recording

    private func startRecording() {
        Task { @MainActor [weak self] in
            guard let self else { return }

            let statusBeforeRequest = Permissions.microphonePermissionStatus
            let isGranted = await Permissions.checkMicrophonePermission()
            guard isGranted else {
                self.state = .error("Microphone access is required. Allow it in System Settings > Privacy & Security > Microphone.")
                self.overlayController?.hide()
                return
            }

            if statusBeforeRequest == .notDetermined {
                self.state = .error("Microphone permission granted. Restarting app to apply changes.")
                Permissions.relaunchApplication()
                return
            }

            do {
                try self.recorder.startRecording()
                self.state = .recording
                self.overlayController?.show(state: .recording)
                self.startOverlayUpdates()
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }

    private func stopRecordingAndTranscribe() {
        let samples = recorder.stopRecording()
        stopOverlayUpdates()
        state = .processing
        overlayController?.show(state: .processing)

        Task { @MainActor in
            do {
                if !transcriptionService.isModelLoaded {
                    let versionString = UserDefaults.standard.string(forKey: "modelVersion") ?? "v3"
                    let version = AppConstants.ModelVersion(rawValue: versionString) ?? .v3
                    try await transcriptionService.loadModel(version: version)
                }

                let result = try await transcriptionService.transcribe(samples)

                if result.text.isEmpty {
                    state = .idle
                    overlayController?.hide()
                    return
                }

                lastTranscription = result.text

                if autoPaste {
                    try await TextPaster.paste(result.text)
                } else {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                }

                if saveHistory, let context = modelContext {
                    let record = TranscriptionRecord(
                        text: result.text,
                        audioDuration: result.audioDuration,
                        processingTime: result.processingTime,
                        modelVersion: transcriptionService.currentModelVersion ?? "v3",
                        language: result.language
                    )
                    context.insert(record)
                    try? context.save()
                }

                state = .idle
                overlayController?.hide()

            } catch {
                state = .error(error.localizedDescription)
                overlayController?.hide()
            }
        }
    }

    // MARK: - Private - Overlay Updates

    private func startOverlayUpdates() {
        overlayUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.overlayController?.updateElapsedTime(self.recorder.elapsedTime)
            self.overlayController?.updateAudioLevel(self.recorder.audioLevel)
        }
    }

    private func stopOverlayUpdates() {
        overlayUpdateTimer?.invalidate()
        overlayUpdateTimer = nil
    }
}
