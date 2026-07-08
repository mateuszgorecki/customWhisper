import Foundation
import Observation
import SwiftData

/// Coordinates the offline meeting-file pipeline: decode → transcribe → (correct) → save.
/// Separate from `AppStateMachine` (live dictation) but shares its `TranscriptionService`,
/// so the Parakeet model loads once and both flows serialize through the same ASR actor.
@Observable
@MainActor
final class MeetingTranscriber {

    // MARK: - State

    enum Phase: Equatable {
        case idle
        case preflight
        case decoding
        case transcribing
        case correcting(Double)
        case done
        case error(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var currentFilename: String?
    private(set) var lastTranscriptID: UUID?

    var isBusy: Bool {
        switch phase {
        case .idle, .done, .error: return false
        default: return true
        }
    }

    var statusText: String {
        switch phase {
        case .idle: return "Ready"
        case .preflight: return "Checking file…"
        case .decoding: return "Decoding audio…"
        case .transcribing: return "Transcribing…"
        case .correcting(let p): return "Correcting… \(Int(p * 100))%"
        case .done: return "Done"
        case .error(let message): return message
        }
    }

    // MARK: - Dependencies

    private let transcriptionService: TranscriptionService
    var modelContext: ModelContext?
    /// Lets dictation veto starting a meeting job while the mic is live (set in App wiring).
    var isDictationActive: () -> Bool = { false }

    init(transcriptionService: TranscriptionService) {
        self.transcriptionService = transcriptionService
    }

    // MARK: - Settings

    private var outputFolder: URL? {
        guard let path = UserDefaults.standard.string(forKey: AppConstants.DefaultsKey.meetingOutputFolder),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private var autoCorrect: Bool {
        UserDefaults.standard.bool(forKey: AppConstants.DefaultsKey.autoCorrectAfterTranscription)
    }

    private var lmStudioBaseURL: String {
        UserDefaults.standard.string(forKey: AppConstants.DefaultsKey.lmStudioBaseURL)
            ?? AppConstants.Meeting.defaultLMStudioBaseURL
    }

    private var correctionModel: String {
        UserDefaults.standard.string(forKey: AppConstants.DefaultsKey.correctionModel)
            ?? AppConstants.Meeting.defaultCorrectionModel
    }

    // MARK: - Pipeline

    /// Full flow for an imported audio file. Non-throwing: failures land in `.error`.
    func transcribe(fileURL: URL) async {
        guard !isBusy else { return }
        guard !isDictationActive() else {
            phase = .error("Can't transcribe a file while dictation is recording. Stop recording first.")
            return
        }

        currentFilename = fileURL.lastPathComponent
        lastTranscriptID = nil
        phase = .preflight

        do {
            // Ensure the model is loaded (shared with dictation).
            if !transcriptionService.isModelLoaded {
                let versionString = UserDefaults.standard.string(forKey: "modelVersion") ?? "v3"
                let version = AppConstants.ModelVersion(rawValue: versionString) ?? .v3
                try await transcriptionService.loadModel(version: version)
            }

            phase = .decoding
            // transcribeFile decodes (ffmpeg) then transcribes (streamed) — report as one step
            // that moves into .transcribing.
            phase = .transcribing
            let result = try await transcriptionService.transcribeFile(url: fileURL)

            guard !result.text.isEmpty else {
                phase = .error("The transcription was empty — no speech detected.")
                return
            }

            let record = MeetingTranscript(
                sourceFilename: fileURL.lastPathComponent,
                duration: result.duration,
                modelVersion: transcriptionService.currentModelVersion ?? "v3",
                rawText: result.text,
                segmentsJSON: result.segments.toJSONString()
            )

            // Write the raw file if an output folder is configured.
            if let folder = outputFolder {
                record.rawFilePath = try? TranscriptExporter
                    .writeRaw(result.text, sourceFilename: record.sourceFilename, to: folder)
                    .path
            }

            modelContext?.insert(record)
            try? modelContext?.save()
            lastTranscriptID = record.id

            if autoCorrect {
                await correct(record)
            } else {
                phase = .done
            }
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    /// Run LM Studio correction on an existing transcript. Non-destructive: the raw text stays.
    func correct(_ record: MeetingTranscript) async {
        phase = .correcting(0)
        let service = TranscriptCorrectionService(baseURL: lmStudioBaseURL, model: correctionModel)

        do {
            let corrected = try await service.correct(record.rawText) { [weak self] progress in
                Task { @MainActor in self?.phase = .correcting(progress) }
            }
            record.correctedText = corrected

            if let folder = outputFolder {
                record.correctedFilePath = try? TranscriptExporter
                    .writeCorrected(corrected, sourceFilename: record.sourceFilename, to: folder)
                    .path
            }

            try? modelContext?.save()
            phase = .done
        } catch {
            // Correction failed — raw transcript is already saved and untouched.
            phase = .error(error.localizedDescription)
        }
    }

    func reset() {
        guard !isBusy else { return }
        phase = .idle
        currentFilename = nil
    }
}
