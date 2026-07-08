import Foundation
import Observation
import FluidAudio

/// Wraps FluidAudio's ASR engine to provide model management and transcription.
///
/// The actual `AsrManager` lives behind a serial actor (`ASRSerialActor`) so live dictation
/// and meeting-file transcription can never touch it concurrently. This class keeps the
/// observable UI state and delegates the model work to that actor.
@Observable
final class TranscriptionService {

    // MARK: - Published State

    private(set) var isModelLoaded = false
    private(set) var isDownloading = false
    private(set) var downloadProgress: Double = 0
    private(set) var currentModelVersion: String?

    // MARK: - Private

    /// Single serialized gate to FluidAudio's AsrManager, shared across every flow.
    let asr = ASRSerialActor()

    // MARK: - Model Management

    /// Download (if needed) and load the ASR model for the given version.
    func loadModel(version: AppConstants.ModelVersion) async throws {
        if currentModelVersion == version.rawValue && isModelLoaded {
            return
        }

        isDownloading = true
        downloadProgress = 0

        do {
            try await asr.loadModel(version: version)

            currentModelVersion = version.rawValue
            isModelLoaded = true
            isDownloading = false
            downloadProgress = 1.0
        } catch {
            isDownloading = false
            isModelLoaded = false
            throw TranscriptionError.modelLoadFailed(error.localizedDescription)
        }
    }

    /// Transcribe an array of 16 kHz mono Float32 PCM samples (live dictation).
    func transcribe(_ samples: [Float]) async throws -> TranscriptionResult {
        guard isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }

        guard !samples.isEmpty else {
            throw TranscriptionError.emptyAudio
        }

        let startTime = Date()
        let result = try await asr.transcribe(samples: samples)
        let processingTime = Date().timeIntervalSince(startTime)
        let audioDuration = Double(samples.count) / 16_000.0

        return TranscriptionResult(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            audioDuration: audioDuration,
            processingTime: processingTime,
            language: nil
        )
    }

    /// Transcribe an audio file (meeting path): decode via ffmpeg, stream through the actor,
    /// and return text + time-stamped segments. Duration comes from ffprobe, NOT the ASR result
    /// (which reports 0 for disk-streamed files).
    func transcribeFile(url: URL) async throws -> MeetingTranscriptionResult {
        guard isModelLoaded else {
            throw TranscriptionError.modelNotLoaded
        }

        // ffmpeg/ffprobe are blocking; keep them off the caller's executor thread.
        let decoded = try await Task.detached(priority: .userInitiated) {
            try AudioFileDecoder.decode(inputURL: url)
        }.value
        defer { AudioFileDecoder.cleanupJob(decoded.jobDirectory) }

        let result = try await asr.transcribe(url: decoded.wavURL)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = Self.groupSegments(from: result.tokenTimings)

        return MeetingTranscriptionResult(
            text: text,
            segments: segments,
            duration: decoded.duration
        )
    }

    /// Clean up resources.
    func cleanup() {
        Task { await asr.cleanup() }
        isModelLoaded = false
        currentModelVersion = nil
    }

    // MARK: - Segment grouping (pure, testable)

    /// Group token-level timings into sentence-ish segments, breaking on sentence-ending
    /// punctuation or on a silence gap ≥ `pauseThreshold`. Returns `[]` when timings are
    /// nil or empty (a valid "transcript without segments" — never a crash).
    static func groupSegments(from tokenTimings: [TokenTiming]?,
                              pauseThreshold: TimeInterval = 0.8) -> [TranscriptSegment] {
        guard let timings = tokenTimings, !timings.isEmpty else { return [] }

        var segments: [TranscriptSegment] = []
        var current: [TokenTiming] = []

        func flush() {
            guard let first = current.first, let last = current.last else { return }
            let text = reconstructText(from: current)
            if !text.isEmpty {
                segments.append(TranscriptSegment(start: first.startTime, end: last.endTime, text: text))
            }
            current.removeAll()
        }

        for token in timings {
            if let previous = current.last, token.startTime - previous.endTime >= pauseThreshold {
                flush()
            }
            current.append(token)

            let trimmed = token.token
                .replacingOccurrences(of: "\u{2581}", with: "")
                .trimmingCharacters(in: .whitespaces)
            if let lastChar = trimmed.last, ".!?".contains(lastChar) {
                flush()
            }
        }
        flush()
        return segments
    }

    /// Reconstruct human text from SentencePiece tokens (▁ marks a word boundary).
    static func reconstructText(from tokens: [TokenTiming]) -> String {
        let joined = tokens.map { $0.token }.joined()
        return joined
            .replacingOccurrences(of: "\u{2581}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Result Types

struct TranscriptionResult {
    let text: String
    let audioDuration: TimeInterval
    let processingTime: TimeInterval
    let language: String?

    var realTimeFactor: Double {
        guard processingTime > 0 else { return 0 }
        return audioDuration / processingTime
    }
}

struct MeetingTranscriptionResult {
    let text: String
    let segments: [TranscriptSegment]
    let duration: TimeInterval
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case emptyAudio
    case modelLoadFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "No transcription model is loaded. Please download a model in Settings."
        case .emptyAudio:
            return "No audio to transcribe. The recording was empty."
        case .modelLoadFailed(let reason):
            return "Failed to load model: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}
