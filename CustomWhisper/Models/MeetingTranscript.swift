import Foundation
import SwiftData

/// A transcription produced from an imported audio file (e.g. a meeting recording),
/// as opposed to `TranscriptionRecord` which stores live dictation results.
/// Keeps the raw ASR transcript and, optionally, an LLM-corrected version, plus
/// time-stamped segments for a future diarization phase.
@Model
final class MeetingTranscript {
    var id: UUID
    var sourceFilename: String
    var date: Date
    var duration: TimeInterval
    var modelVersion: String
    var language: String?
    var rawText: String
    var correctedText: String?
    /// JSON-encoded `[TranscriptSegment]`.
    var segmentsJSON: String
    var rawFilePath: String?
    var correctedFilePath: String?

    init(
        sourceFilename: String,
        duration: TimeInterval,
        modelVersion: String,
        rawText: String,
        segmentsJSON: String = "[]",
        language: String? = nil,
        correctedText: String? = nil,
        rawFilePath: String? = nil,
        correctedFilePath: String? = nil
    ) {
        self.id = UUID()
        self.sourceFilename = sourceFilename
        self.date = Date()
        self.duration = duration
        self.modelVersion = modelVersion
        self.rawText = rawText
        self.segmentsJSON = segmentsJSON
        self.language = language
        self.correctedText = correctedText
        self.rawFilePath = rawFilePath
        self.correctedFilePath = correctedFilePath
    }

    // MARK: - Derived

    var segments: [TranscriptSegment] {
        [TranscriptSegment].fromJSONString(segmentsJSON)
    }

    var hasCorrection: Bool {
        !(correctedText ?? "").isEmpty
    }

    var formattedDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    var formattedDuration: String {
        let seconds = Int(duration)
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes < 60 {
            return "\(minutes)m \(remainder)s"
        }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        return "\(hours)h \(remMinutes)m"
    }

    var textPreview: String {
        let source = correctedText ?? rawText
        let maxLength = 120
        if source.count <= maxLength { return source }
        return String(source.prefix(maxLength)) + "..."
    }
}
