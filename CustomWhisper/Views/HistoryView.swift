import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TranscriptionRecord.date, order: .reverse)
    private var records: [TranscriptionRecord]

    @State private var searchText = ""
    @State private var selectedRecord: TranscriptionRecord?
    @State private var showDeleteConfirmation = false

    private var filteredRecords: [TranscriptionRecord] {
        if searchText.isEmpty {
            return records
        }
        return records.filter { $0.text.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if filteredRecords.isEmpty {
                emptyState
            } else {
                recordsList
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbar: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search transcriptions...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
            }

            Spacer()

            Text("\(filteredRecords.count) items")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !records.isEmpty {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .confirmationDialog("Delete all transcriptions?", isPresented: $showDeleteConfirmation) {
                    Button("Delete All", role: .destructive) {
                        deleteAll()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will permanently delete all \(records.count) transcription records.")
                }
            }
        }
        .padding(16)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            if searchText.isEmpty {
                Text("No transcriptions yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Use the keyboard shortcut to start dictating.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No results for \"\(searchText)\"")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Records List

    @ViewBuilder
    private var recordsList: some View {
        List(selection: $selectedRecord) {
            ForEach(filteredRecords) { record in
                HistoryRow(record: record)
                    .tag(record)
                    .contextMenu {
                        Button("Copy Text") {
                            copyToClipboard(record.text)
                        }
                        Divider()
                        Button("Delete", role: .destructive) {
                            deleteRecord(record)
                        }
                    }
            }
            .onDelete(perform: deleteRecords)
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Actions

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func deleteRecord(_ record: TranscriptionRecord) {
        modelContext.delete(record)
        try? modelContext.save()
    }

    private func deleteRecords(at offsets: IndexSet) {
        for index in offsets {
            let record = filteredRecords[index]
            modelContext.delete(record)
        }
        try? modelContext.save()
    }

    private func deleteAll() {
        for record in records {
            modelContext.delete(record)
        }
        try? modelContext.save()
    }
}

// MARK: - History Row

struct HistoryRow: View {
    let record: TranscriptionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(record.formattedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    Label(record.formattedDuration, systemImage: "waveform")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Label(record.formattedProcessingTime, systemImage: "bolt")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Text("v\(record.modelVersion)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            Capsule().fill(.quaternary)
                        }
                        .foregroundStyle(.secondary)
                }
            }

            Text(record.textPreview)
                .font(.body)
                .lineLimit(3)

            HStack {
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(record.text, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(.vertical, 4)
    }
}
