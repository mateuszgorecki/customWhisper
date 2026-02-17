import XCTest
@testable import CustomWhisper

final class AudioRecorderTests: XCTestCase {

    func testInitialState() {
        let recorder = AudioRecorder()
        XCTAssertFalse(recorder.isRecording)
        XCTAssertEqual(recorder.elapsedTime, 0)
        XCTAssertEqual(recorder.audioLevel, 0)
    }

    func testStopRecordingWhenNotRecordingReturnsEmpty() {
        let recorder = AudioRecorder()
        let samples = recorder.stopRecording()
        XCTAssertTrue(samples.isEmpty)
    }

    func testCancelRecordingWhenNotRecordingIsNoOp() {
        let recorder = AudioRecorder()
        recorder.cancelRecording()
        XCTAssertFalse(recorder.isRecording)
    }

    func testRecordingErrorDescriptions() {
        let noInput = RecordingError.noInputDevice
        XCTAssertNotNil(noInput.errorDescription)
        XCTAssertTrue(noInput.errorDescription!.contains("input device"))

        let converterFail = RecordingError.converterCreationFailed
        XCTAssertNotNil(converterFail.errorDescription)
        XCTAssertTrue(converterFail.errorDescription!.contains("converter"))
    }
}
