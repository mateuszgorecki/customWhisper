import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit

struct MeetingsView: View {
    @Environment(MeetingTranscriber.self) private var transcriber
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MeetingTranscript.date, order: .reverse)
    private var transcripts: [MeetingTranscript]

    @State private var isImporterPresented = false
    @State private var isDropTargeted = false
    @State private var selection: MeetingTranscript?

    private var importContentTypes: [UTType] {
        var types: [UTType] = [.audio]
        for ext in AppConstants.Meeting.acceptedExtensions {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            if let selection {
                MeetingDetailView(transcript: selection)
                    .id(selection.id)
            } else {
                placeholder
            }
        }
        .fileImporter(isPresented: $isImporterPresented,
                      allowedContentTypes: importContentTypes,
                      allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                startTranscription(url)
            }
        }
    }

    // MARK: - Sidebar

    @ViewBuilder
    private var sidebar: some View {
        VStack(spacing: 0) {
            importBar

            if transcriber.isBusy || isErrorPhase {
                statusStrip
            }

            if transcripts.isEmpty {
                emptyState
            } else {
                List(selection: $selection) {
                    ForEach(transcripts) { transcript in
                        MeetingRow(transcript: transcript)
                            .tag(transcript)
                            .contextMenu {
                                Button("Copy Text") {
                                    copy(transcript.correctedText ?? transcript.rawText)
                                }
                                Button("Delete", role: .destructive) {
                                    delete(transcript)
                                }
                            }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var isErrorPhase: Bool {
        if case .error = transcriber.phase { return true }
        return false
    }

    @ViewBuilder
    private var importBar: some View {
        VStack(spacing: 8) {
            Button {
                isImporterPresented = true
            } label: {
                Label("Import audio file…", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(transcriber.isBusy)

            Text("or drop a file here")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .foregroundStyle(isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.4))
        }
        .padding(12)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    @ViewBuilder
    private var statusStrip: some View {
        HStack(spacing: 8) {
            if transcriber.isBusy {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Text(transcriber.statusText)
                .font(.caption)
                .foregroundStyle(isErrorPhase ? .orange : .secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.wave.2")
                .font(.system(size: 40))
                .foregroundStyle(.quaternary)
            Text("No meeting transcripts yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Import a recording to transcribe it locally.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 44))
                .foregroundStyle(.quaternary)
            Text("Select a transcript")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func startTranscription(_ url: URL) {
        transcriber.modelContext = modelContext
        Task { await transcriber.transcribe(fileURL: url) }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !transcriber.isBusy, let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            var resolved: URL?
            if let data = item as? Data {
                resolved = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                resolved = url
            }
            if let resolved {
                Task { @MainActor in startTranscription(resolved) }
            }
        }
        return true
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func delete(_ transcript: MeetingTranscript) {
        if selection?.id == transcript.id { selection = nil }
        modelContext.delete(transcript)
        try? modelContext.save()
    }
}

// MARK: - Row

private struct MeetingRow: View {
    let transcript: MeetingTranscript

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(transcript.sourceFilename)
                .font(.body)
                .lineLimit(1)
            HStack(spacing: 8) {
                Text(transcript.formattedDate)
                Text("·")
                Label(transcript.formattedDuration, systemImage: "waveform")
                if transcript.hasCorrection {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
