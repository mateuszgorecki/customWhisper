import XCTest
import FluidAudio
@testable import CustomWhisper

final class SegmentGroupingTests: XCTestCase {

    private func token(_ text: String, _ start: TimeInterval, _ end: TimeInterval) -> TokenTiming {
        TokenTiming(token: text, tokenId: 0, startTime: start, endTime: end, confidence: 1)
    }

    // MARK: - Nil / empty (must not crash)

    func testNilTimingsReturnsEmpty() {
        XCTAssertEqual(TranscriptionService.groupSegments(from: nil), [])
    }

    func testEmptyTimingsReturnsEmpty() {
        XCTAssertEqual(TranscriptionService.groupSegments(from: []), [])
    }

    // MARK: - Punctuation boundaries

    func testSentencePunctuationSplits() {
        let timings = [
            token("\u{2581}Hello", 0.0, 0.4),
            token("\u{2581}world.", 0.4, 0.8),
            token("\u{2581}Bye", 1.0, 1.3),
        ]
        let segments = TranscriptionService.groupSegments(from: timings, pauseThreshold: 5.0)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "Hello world.")
        XCTAssertEqual(segments[0].start, 0.0)
        XCTAssertEqual(segments[0].end, 0.8)
        XCTAssertEqual(segments[1].text, "Bye")
    }

    // MARK: - Pause boundaries

    func testPauseGapSplits() {
        let timings = [
            token("\u{2581}one", 0.0, 0.3),
            token("\u{2581}two", 0.3, 0.6),
            // 1.5s gap -> new segment
            token("\u{2581}three", 2.1, 2.4),
        ]
        let segments = TranscriptionService.groupSegments(from: timings, pauseThreshold: 0.8)
        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments[0].text, "one two")
        XCTAssertEqual(segments[1].text, "three")
    }

    // MARK: - No boundaries -> single segment

    func testNoBoundariesYieldsSingleSegment() {
        let timings = [
            token("\u{2581}a", 0.0, 0.2),
            token("\u{2581}b", 0.2, 0.4),
            token("\u{2581}c", 0.4, 0.6),
        ]
        let segments = TranscriptionService.groupSegments(from: timings, pauseThreshold: 5.0)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].text, "a b c")
        XCTAssertEqual(segments[0].start, 0.0)
        XCTAssertEqual(segments[0].end, 0.6)
    }

    // MARK: - JSON round-trip

    func testSegmentsJSONRoundTrip() {
        let segments = [
            TranscriptSegment(start: 0, end: 1, text: "hi"),
            TranscriptSegment(start: 1, end: 2, text: "there"),
        ]
        let json = segments.toJSONString()
        let restored = [TranscriptSegment].fromJSONString(json)
        XCTAssertEqual(restored.map(\.text), ["hi", "there"])
        XCTAssertEqual(restored.map(\.start), [0, 1])
    }

    func testFromJSONStringInvalidReturnsEmpty() {
        XCTAssertEqual([TranscriptSegment].fromJSONString("not json"), [])
    }
}
