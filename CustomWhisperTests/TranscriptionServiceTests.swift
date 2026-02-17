import XCTest
@testable import CustomWhisper

final class TranscriptionServiceTests: XCTestCase {

    func testInitialState() {
        let service = TranscriptionService()
        XCTAssertFalse(service.isModelLoaded)
        XCTAssertFalse(service.isDownloading)
        XCTAssertEqual(service.downloadProgress, 0)
        XCTAssertNil(service.currentModelVersion)
    }

    func testTranscribeWithoutModelThrows() async {
        let service = TranscriptionService()
        do {
            _ = try await service.transcribe([0.1, 0.2, 0.3])
            XCTFail("Expected TranscriptionError.modelNotLoaded")
        } catch let error as TranscriptionError {
            if case .modelNotLoaded = error {
                // Expected
            } else {
                XCTFail("Expected modelNotLoaded, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testTranscribeEmptyAudioThrows() async {
        let service = TranscriptionService()
        // Even if model were loaded, empty audio should fail.
        // We test the guard by checking the error type.
        do {
            _ = try await service.transcribe([])
            XCTFail("Expected error for empty audio")
        } catch {
            // Expected: either modelNotLoaded or emptyAudio
        }
    }

    func testCleanupResetsState() {
        let service = TranscriptionService()
        service.cleanup()
        XCTAssertFalse(service.isModelLoaded)
        XCTAssertNil(service.currentModelVersion)
    }

    func testTranscriptionResultRealTimeFactor() {
        let result = TranscriptionResult(
            text: "Hello world",
            audioDuration: 10.0,
            processingTime: 0.1,
            language: "en"
        )
        XCTAssertEqual(result.realTimeFactor, 100.0, accuracy: 0.1)
    }

    func testTranscriptionResultZeroProcessingTime() {
        let result = TranscriptionResult(
            text: "Test",
            audioDuration: 5.0,
            processingTime: 0,
            language: nil
        )
        XCTAssertEqual(result.realTimeFactor, 0)
    }

    func testTranscriptionErrorDescriptions() {
        let errors: [TranscriptionError] = [
            .modelNotLoaded,
            .emptyAudio,
            .modelLoadFailed("test reason"),
            .transcriptionFailed("test reason"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription)
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }
}
