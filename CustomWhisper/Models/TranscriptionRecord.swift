import Foundation
import SwiftData

@Model
final class TranscriptionRecord {
    var id: UUID
    var text: String
    var date: Date
    var audioDuration: TimeInterval
    var processingTime: TimeInterval
    var modelVersion: String
    var language: String?

    init(
        text: String,
        audioDuration: TimeInterval,
        processingTime: TimeInterval,
        modelVersion: String,
        language: String? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.audioDuration = audioDuration
        self.processingTime = processingTime
        self.modelVersion = modelVersion
        self.language = language
    }

    var formattedDate: String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    var formattedDuration: String {
        let seconds = Int(audioDuration)
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        let remainder = seconds % 60
        return "\(minutes)m \(remainder)s"
    }

    var formattedProcessingTime: String {
        String(format: "%.1fs", processingTime)
    }

    var textPreview: String {
        let maxLength = 120
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "..."
    }
}
