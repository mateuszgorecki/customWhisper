import SwiftUI
import SwiftData
import KeyboardShortcuts

@main
struct CustomWhisperApp: App {
    @State private var stateMachine = AppStateMachine()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(stateMachine)
                .onAppear {
                    setupOnFirstLaunch()
                }
        }
        .modelContainer(for: TranscriptionRecord.self)
        .defaultSize(width: 600, height: 500)
    }

    private func setupOnFirstLaunch() {
        let overlayController = RecordingOverlayController()
        stateMachine.overlayController = overlayController

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
