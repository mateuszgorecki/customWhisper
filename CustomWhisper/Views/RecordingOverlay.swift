import SwiftUI
import AppKit

// MARK: - Overlay State

enum OverlayDisplayState {
    case recording
    case processing
}

// MARK: - NSPanel-based Overlay Controller

/// Manages a floating, non-activating NSPanel that shows recording/processing status.
/// The panel floats above all windows and never steals focus from the active app.
final class RecordingOverlayController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<RecordingOverlayContent>?

    private let overlayModel = OverlayViewModel()

    func show(state: OverlayDisplayState) {
        overlayModel.displayState = state
        overlayModel.isVisible = true

        if panel == nil {
            createPanel()
        }

        panel?.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel?.animator().alphaValue = 1.0
        }
    }

    func hide() {
        overlayModel.isVisible = false

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            panel?.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        })
    }

    func updateElapsedTime(_ time: TimeInterval) {
        overlayModel.elapsedTime = time
    }

    func updateAudioLevel(_ level: Float) {
        overlayModel.audioLevel = level
    }

    // MARK: - Private

    private func createPanel() {
        let contentView = RecordingOverlayContent(model: overlayModel)
        let hosting = NSHostingView(rootView: contentView)
        hosting.frame = NSRect(x: 0, y: 0, width: 220, height: 56)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 56),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting
        panel.alphaValue = 0

        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - 110
            let y = screenFrame.maxY - 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        self.panel = panel
        self.hostingView = hosting
    }
}

// MARK: - View Model

@Observable
final class OverlayViewModel {
    var isVisible = false
    var displayState: OverlayDisplayState = .recording
    var elapsedTime: TimeInterval = 0
    var audioLevel: Float = 0

    var formattedTime: String {
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - SwiftUI Overlay Content

struct RecordingOverlayContent: View {
    let model: OverlayViewModel

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(model.displayState == .recording ? Color.red : Color.blue)
                    .frame(width: 32, height: 32)
                    .scaleEffect(pulseScale)
                    .opacity(0.3)

                if model.displayState == .recording {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayState == .recording ? "Recording" : "Transcribing")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                if model.displayState == .recording {
                    Text(model.formattedTime)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Please wait...")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        }
        .frame(width: 220, height: 56)
        .onAppear {
            startPulse()
        }
        .onChange(of: model.displayState) { _, _ in
            startPulse()
        }
    }

    private func startPulse() {
        if model.displayState == .recording {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                pulseScale = 1.3
            }
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                pulseScale = 1.0
            }
        }
    }
}
