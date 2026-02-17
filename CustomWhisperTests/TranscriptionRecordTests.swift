import XCTest
@testable import CustomWhisper

final class TranscriptionRecordTests: XCTestCase {

    func testRecordCreation() {
        let record = TranscriptionRecord(
            text: "Hello world",
            audioDuration: 5.2,
            processingTime: 0.3,
            modelVersion: "v3",
            language: "en"
        )

        XCTAssertEqual(record.text, "Hello world")
        XCTAssertEqual(record.audioDuration, 5.2, accuracy: 0.01)
        XCTAssertEqual(record.processingTime, 0.3, accuracy: 0.01)
        XCTAssertEqual(record.modelVersion, "v3")
        XCTAssertEqual(record.language, "en")
        XCTAssertNotNil(record.id)
        XCTAssertNotNil(record.date)
    }

    func testFormattedDurationSeconds() {
        let record = TranscriptionRecord(
            text: "Test",
            audioDuration: 45.0,
            processingTime: 0.1,
            modelVersion: "v3"
        )
        XCTAssertEqual(record.formattedDuration, "45s")
    }

    func testFormattedDurationMinutes() {
        let record = TranscriptionRecord(
            text: "Test",
            audioDuration: 125.0,
            processingTime: 0.1,
            modelVersion: "v3"
        )
        XCTAssertEqual(record.formattedDuration, "2m 5s")
    }

    func testFormattedProcessingTime() {
        let record = TranscriptionRecord(
            text: "Test",
            audioDuration: 10.0,
            processingTime: 0.456,
            modelVersion: "v3"
        )
        XCTAssertEqual(record.formattedProcessingTime, "0.5s")
    }

    func testTextPreviewShort() {
        let record = TranscriptionRecord(
            text: "Short text",
            audioDuration: 1.0,
            processingTime: 0.1,
            modelVersion: "v3"
        )
        XCTAssertEqual(record.textPreview, "Short text")
    }

    func testTextPreviewLong() {
        let longText = String(repeating: "A", count: 200)
        let record = TranscriptionRecord(
            text: longText,
            audioDuration: 10.0,
            processingTime: 0.5,
            modelVersion: "v3"
        )
        XCTAssertTrue(record.textPreview.hasSuffix("..."))
        XCTAssertEqual(record.textPreview.count, 123) // 120 chars + "..."
    }
}
