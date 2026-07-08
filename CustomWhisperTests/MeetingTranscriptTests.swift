import XCTest
@testable import CustomWhisper

final class MeetingTranscriptTests: XCTestCase {

    func testFormattedDurationHoursMinutes() {
        let record = MeetingTranscript(sourceFilename: "m.ogg", duration: 3_725, modelVersion: "v3", rawText: "hi")
        XCTAssertEqual(record.formattedDuration, "1h 2m")
    }

    func testFormattedDurationMinutes() {
        let record = MeetingTranscript(sourceFilename: "m.ogg", duration: 125, modelVersion: "v3", rawText: "hi")
        XCTAssertEqual(record.formattedDuration, "2m 5s")
    }

    func testHasCorrection() {
        let record = MeetingTranscript(sourceFilename: "m.ogg", duration: 1, modelVersion: "v3", rawText: "raw")
        XCTAssertFalse(record.hasCorrection)
        record.correctedText = "fixed"
        XCTAssertTrue(record.hasCorrection)
    }

    func testTextPreviewPrefersCorrected() {
        let record = MeetingTranscript(sourceFilename: "m.ogg", duration: 1, modelVersion: "v3", rawText: "raw text")
        XCTAssertEqual(record.textPreview, "raw text")
        record.correctedText = "corrected text"
        XCTAssertEqual(record.textPreview, "corrected text")
    }

    func testSegmentsDecodeFromJSON() {
        let segments = [TranscriptSegment(start: 0, end: 1, text: "a")]
        let record = MeetingTranscript(
            sourceFilename: "m.ogg", duration: 1, modelVersion: "v3",
            rawText: "a", segmentsJSON: segments.toJSONString()
        )
        XCTAssertEqual(record.segments.map(\.text), ["a"])
    }
}
