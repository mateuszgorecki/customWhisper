import SwiftUI
import SwiftData
import KeyboardShortcuts

@main
struct CustomWhisperApp: App {
    @State private var stateMachine: AppStateMachine
    @State private var meetingTranscriber: MeetingTranscriber
    @Environment(\.openWindow) private var openWindow

    init() {
        let machine = AppStateMachine()
        _stateMachine = State(initialValue: machine)
        _meetingTranscriber = State(initialValue: MeetingTranscriber(transcriptionService: machine.transcriptionService))
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(stateMachine)
                .environment(meetingTranscriber)
                .onAppear {
                    setupOnFirstLaunch()
                }
        }
        .modelContainer(for: [TranscriptionRecord.self, MeetingTranscript.self])
        .defaultSize(width: 600, height: 500)
    }

    private func setupOnFirstLaunch() {
        let overlayController = RecordingOverlayController()
        stateMachine.overlayController = overlayController

        // Cross-flow vetoes: no dictation while a meeting job runs, and vice-versa.
        stateMachine.isMeetingBusy = { [weak meetingTranscriber] in
            meetingTranscriber?.isBusy ?? false
        }
        meetingTranscriber.isDictationActive = { [weak stateMachine] in
            stateMachine?.recorder.isRecording ?? false
        }

        // Remove any meeting temp dirs orphaned by a previous crash/kill.
        AudioFileDecoder.sweepOrphanedJobs()

        Task {
            await stateMachine.loadModelFromSettings()
        }

        if Permissions.isAccessibilityStale {
            print("[Permissions] Accessibility permission is stale (TCC entry outdated after rebuild). Auto-paste will not work until re-granted via Settings > Permissions.")
        } else if !Permissions.isAccessibilityGranted {
            Permissions.requestAccessibility()
        }
    }
}
