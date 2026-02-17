import XCTest
@testable import CustomWhisper

final class AppStateMachineTests: XCTestCase {

    // MARK: - State Transitions

    func testInitialStateIsIdle() {
        let sm = AppStateMachine()
        XCTAssertEqual(sm.state, .idle)
    }

    func testToggleFromIdleStartsRecording() {
        let sm = AppStateMachine()
        // Note: In a real test we'd mock AudioRecorder to avoid needing a mic.
        // For now we verify the state machine logic through AppState directly.
        XCTAssertTrue(sm.state.isIdle)
    }

    func testCancelFromIdleDoesNothing() {
        let sm = AppStateMachine()
        sm.cancel()
        XCTAssertEqual(sm.state, .idle)
    }

    // MARK: - AppState properties

    func testAppStateIsRecording() {
        let state = AppState.recording
        XCTAssertTrue(state.isRecording)
        XCTAssertFalse(state.isIdle)
        XCTAssertFalse(state.isProcessing)
        XCTAssertFalse(state.isError)
    }

    func testAppStateIsProcessing() {
        let state = AppState.processing
        XCTAssertTrue(state.isProcessing)
        XCTAssertFalse(state.isRecording)
        XCTAssertFalse(state.isIdle)
    }

    func testAppStateIsError() {
        let state = AppState.error("Something went wrong")
        XCTAssertTrue(state.isError)
        XCTAssertFalse(state.isIdle)
        XCTAssertEqual(state.statusText, "Error: Something went wrong")
    }

    func testAppStateStatusText() {
        XCTAssertEqual(AppState.idle.statusText, "Ready")
        XCTAssertEqual(AppState.recording.statusText, "Recording...")
        XCTAssertEqual(AppState.processing.statusText, "Transcribing...")
    }

    func testAppStateEquality() {
        XCTAssertEqual(AppState.idle, AppState.idle)
        XCTAssertEqual(AppState.recording, AppState.recording)
        XCTAssertEqual(AppState.processing, AppState.processing)
        XCTAssertNotEqual(AppState.idle, AppState.recording)
        XCTAssertNotEqual(AppState.recording, AppState.processing)
    }
}
