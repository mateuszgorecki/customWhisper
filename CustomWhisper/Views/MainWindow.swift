import SwiftUI
import SwiftData

struct MainWindow: View {
    @Environment(AppStateMachine.self) private var stateMachine
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }

            MeetingsView()
                .tabItem {
                    Label("Meetings", systemImage: "person.wave.2")
                }

            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            stateMachine.modelContext = modelContext
        }
        .overlay(alignment: .bottom) {
            statusBar
        }
    }

    @ViewBuilder
    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(stateMachine.state.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if stateMachine.transcriptionService.isModelLoaded {
                Text("Model: Parakeet \(stateMachine.transcriptionService.currentModelVersion ?? "v3")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if stateMachine.transcriptionService.isDownloading {
                ProgressView(value: stateMachine.transcriptionService.downloadProgress)
                    .frame(width: 100)

                Text("Downloading model...")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No model loaded")
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.7))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var statusColor: Color {
        switch stateMachine.state {
        case .idle: return .green
        case .recording: return .red
        case .processing: return .orange
        case .error: return .red
        }
    }
}
