import Foundation

/// A time-stamped slice of a transcript. Grouped from the ASR model's token-level
/// timings so a future diarization phase can attach speaker labels to time ranges.
/// The UI shows plain text; segments are persisted alongside it as JSON.
struct TranscriptSegment: Codable, Sendable, Identifiable, Equatable {
    var id: UUID
    let start: TimeInterval
    let end: TimeInterval
    let text: String

    init(id: UUID = UUID(), start: TimeInterval, end: TimeInterval, text: String) {
        self.id = id
        self.start = start
        self.end = end
        self.text = text
    }
}

extension Array where Element == TranscriptSegment {

    /// Serialize to a JSON string for storage in SwiftData. Returns "[]" on failure.
    func toJSONString() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    /// Reconstruct segments from a stored JSON string. Returns [] on failure.
    static func fromJSONString(_ string: String) -> [TranscriptSegment] {
        guard let data = string.data(using: .utf8),
              let segments = try? JSONDecoder().decode([TranscriptSegment].self, from: data) else {
            return []
        }
        return segments
    }
}
