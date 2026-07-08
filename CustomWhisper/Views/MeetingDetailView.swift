import SwiftUI
import AppKit

struct MeetingDetailView: View {
    @Environment(MeetingTranscriber.self) private var transcriber
    @Environment(\.modelContext) private var modelContext
    let transcript: MeetingTranscript

    enum Tab: Hashable { case raw, corrected }
    @State private var tab: Tab = .raw

    private var isCorrecting: Bool {
        if case .correcting = transcriber.phase { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            transcriptArea
        }
        .onAppear {
            tab = transcript.hasCorrection ? .corrected : .raw
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(transcript.sourceFilename)
                .font(.title3.weight(.semibold))
                .lineLimit(1)

            HStack(spacing: 10) {
                Label(transcript.formattedDate, systemImage: "calendar")
                Label(transcript.formattedDuration, systemImage: "waveform")
                Text("Parakeet \(transcript.modelVersion)")
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background { Capsule().fill(.quaternary) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                if transcript.hasCorrection {
                    Picker("", selection: $tab) {
                        Text("Raw").tag(Tab.raw)
                        Text("Corrected").tag(Tab.corrected)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 200)
                }

                Spacer()

                Button {
                    correct()
                } label: {
                    if isCorrecting {
                        Label(transcriber.statusText, systemImage: "wand.and.stars")
                    } else {
                        Label(transcript.hasCorrection ? "Re-correct" : "Correct with LM Studio",
                              systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(transcriber.isBusy)

                Button {
                    copy(currentText)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if let path = currentFilePath {
                    Button {
                        revealInFinder(path)
                    } label: {
                        Label("Reveal", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcriptArea: some View {
        ScrollView {
            Text(currentText.isEmpty ? "—" : currentText)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }

    // MARK: - Helpers

    private var currentText: String {
        switch tab {
        case .raw: return transcript.rawText
        case .corrected: return transcript.correctedText ?? transcript.rawText
        }
    }

    private var currentFilePath: String? {
        switch tab {
        case .raw: return transcript.rawFilePath
        case .corrected: return transcript.correctedFilePath ?? transcript.rawFilePath
        }
    }

    private func correct() {
        transcriber.modelContext = modelContext
        Task {
            await transcriber.correct(transcript)
            if transcript.hasCorrection { tab = .corrected }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
