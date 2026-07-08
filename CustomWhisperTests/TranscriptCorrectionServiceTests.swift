import XCTest
@testable import CustomWhisper

/// Deterministic HTTP stub for the correction service.
private final class MockHTTPClient: HTTPClient, @unchecked Sendable {
    var handler: (URLRequest) throws -> (Data, URLResponse)
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping (URLRequest) throws -> (Data, URLResponse)) {
        self.handler = handler
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        return try handler(request)
    }
}

private func httpResponse(_ url: URL, _ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
}

private func chatJSON(content: String) -> Data {
    let obj: [String: Any] = ["choices": [["message": ["role": "assistant", "content": content]]]]
    return try! JSONSerialization.data(withJSONObject: obj)
}

final class TranscriptCorrectionServiceTests: XCTestCase {

    // MARK: - Sentinels

    func testSentinelPayloadRoundTrip() {
        let paragraphs = ["first para", "second para"]
        let payload = TranscriptCorrectionService.buildSentinelPayload(paragraphs)
        XCTAssertTrue(payload.contains(TranscriptCorrectionService.marker(0)))
        XCTAssertTrue(payload.contains(TranscriptCorrectionService.marker(1)))
        XCTAssertTrue(payload.contains(TranscriptCorrectionService.endSentinel))

        let parsed = TranscriptCorrectionService.parseSentinelResponse(payload, expectedCount: 2)
        XCTAssertEqual(parsed, ["first para", "second para"])
    }

    func testParseRejectsMissingSentinel() {
        // Only SEG:0 present, expecting 2 -> nil.
        let response = "\(TranscriptCorrectionService.marker(0))\nfixed\n\(TranscriptCorrectionService.endSentinel)"
        XCTAssertNil(TranscriptCorrectionService.parseSentinelResponse(response, expectedCount: 2))
    }

    func testParseRejectsReorderedSentinels() {
        let m0 = TranscriptCorrectionService.marker(0)
        let m1 = TranscriptCorrectionService.marker(1)
        let end = TranscriptCorrectionService.endSentinel
        // SEG:1 appears before SEG:0 -> ordered search for 0 then 1-after-0 fails.
        let response = "\(m1)\nB\n\(m0)\nA\n\(end)"
        XCTAssertNil(TranscriptCorrectionService.parseSentinelResponse(response, expectedCount: 2))
    }

    func testParseRejectsCorruptedMarker() {
        let response = "SEG:0\nfixed\n\(TranscriptCorrectionService.endSentinel)"
        XCTAssertNil(TranscriptCorrectionService.parseSentinelResponse(response, expectedCount: 1))
    }

    // MARK: - Batching

    func testBatchingSplitsByMaxChars() {
        let text = "aaaa\nbbbb\ncccc"
        let batches = TranscriptCorrectionService.batchParagraphs(text, maxChars: 10)
        // Each paragraph ~5 chars incl newline; 10-char cap groups two then one.
        XCTAssertEqual(batches.count, 2)
        XCTAssertEqual(batches[0], ["aaaa", "bbbb"])
        XCTAssertEqual(batches[1], ["cccc"])
    }

    func testBatchingSkipsBlankLines() {
        let batches = TranscriptCorrectionService.batchParagraphs("a\n\n\nb", maxChars: 1000)
        XCTAssertEqual(batches, [["a", "b"]])
    }

    // MARK: - Long-paragraph splitting (the newline-free-transcript fix)

    func testSplitLongParagraphLeavesShortTextUntouched() {
        let text = "This is short. It fits."
        XCTAssertEqual(TranscriptCorrectionService.splitLongParagraph(text, maxChars: 1000), [text])
    }

    func testSplitLongParagraphBreaksOnSentences() {
        // Five ~20-char sentences, no newlines; cap forces multiple chunks each ≤ cap.
        let sentence = "Ala ma kota i psa. "
        let text = String(repeating: sentence, count: 10).trimmingCharacters(in: .whitespaces)
        let chunks = TranscriptCorrectionService.splitLongParagraph(text, maxChars: 60)
        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 60)
        }
    }

    func testSplitLongParagraphHardCutsWordWithoutPunctuation() {
        // No sentence punctuation, no spaces, longer than the cap → hard character cut.
        let text = String(repeating: "x", count: 250)
        let chunks = TranscriptCorrectionService.splitLongParagraph(text, maxChars: 100)
        XCTAssertEqual(chunks.count, 3)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, 100)
        }
        XCTAssertEqual(chunks.joined().count, 250)
    }

    func testBatchingSplitsNewlineFreeTranscript() {
        // Regression: an ASR transcript is one continuous string with no '\n'. It must
        // still be broken into multiple batches instead of one oversized request.
        let text = String(repeating: "To jest zdanie testowe. ", count: 100)
            .trimmingCharacters(in: .whitespaces)
        let batches = TranscriptCorrectionService.batchParagraphs(text, maxChars: 200)
        XCTAssertGreaterThan(batches.count, 1)
        for batch in batches {
            let total = batch.reduce(0) { $0 + $1.count }
            XCTAssertLessThanOrEqual(total, 200 + 1) // greedy grouping stays under the cap
        }
    }

    // MARK: - Context-window budget

    func testRecommendedMaxCharsGrowsWithContext() {
        let small = TranscriptCorrectionService.recommendedMaxChars(contextTokens: 4096)
        let large = TranscriptCorrectionService.recommendedMaxChars(contextTokens: 16384)
        XCTAssertGreaterThan(large, small)
        XCTAssertGreaterThanOrEqual(small, 800) // never below the floor
    }

    func testRecommendedMaxCharsSmallContextStaysSafe() {
        // Input chars + reasoning echo must plausibly fit a small window. With echoFactor 3
        // and ~2 chars/token, a 4096 window should not budget anywhere near 4096 chars.
        let chars = TranscriptCorrectionService.recommendedMaxChars(contextTokens: 4096)
        XCTAssertLessThan(chars, 3000)
    }

    func testParseContextLengthPrefersLoadedWindow() {
        let obj: [String: Any] = ["data": [
            ["id": "m", "max_context_length": 32768, "loaded_context_length": 8192],
        ]]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        XCTAssertEqual(TranscriptCorrectionService.parseContextLength(from: data, model: "m"), 8192)
    }

    func testParseContextLengthDiscountsMaxWhenNoLoaded() {
        let obj: [String: Any] = ["data": [["id": "m", "max_context_length": 8000]]]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        // Halved by the safety factor rather than trusting the raw max.
        XCTAssertEqual(TranscriptCorrectionService.parseContextLength(from: data, model: "m"), 4000)
    }

    func testParseContextLengthNilForMissingModelOrGarbage() {
        let obj: [String: Any] = ["data": [["id": "other", "loaded_context_length": 8192]]]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        XCTAssertNil(TranscriptCorrectionService.parseContextLength(from: data, model: "m"))
        XCTAssertNil(TranscriptCorrectionService.parseContextLength(from: Data("nope".utf8), model: "m"))
    }

    // MARK: - Per-batch error isolation

    func testCorrectKeepsRawForFailedBatchAndContinues() async throws {
        // First chat batch fails with HTTP 400; the rest succeed. Result must be complete.
        let mock = MockHTTPClient { request in
            let path = request.url!.path
            if path.hasSuffix("/api/v0/models") {
                return (Data("{}".utf8), httpResponse(request.url!, 404)) // no detection
            }
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            let userContent = messages.last!["content"]!
            if userContent.contains("BOOM") {
                return (Data("context overflow".utf8), httpResponse(request.url!, 400))
            }
            let count = userContent.components(separatedBy: "⟦SEG:").count - 1
            var lines: [String] = []
            for i in 0..<count {
                lines.append(TranscriptCorrectionService.marker(i))
                lines.append("OK\(i)")
            }
            lines.append(TranscriptCorrectionService.endSentinel)
            return (chatJSON(content: lines.joined(separator: "\n")), httpResponse(request.url!, 200))
        }
        let service = TranscriptCorrectionService(client: mock, maxCharsPerBatch: 20)
        // Two paragraphs → two batches (cap 20). One carries the BOOM sentinel word.
        let result = try await service.correct("keep this line\nBOOM here now")
        XCTAssertTrue(result.contains("BOOM here now")) // failed batch kept raw
        XCTAssertTrue(result.contains("OK0"))           // successful batch corrected
    }

    func testCorrectThrowsWhenEveryBatchFails() async {
        let mock = MockHTTPClient { request in
            (Data("down".utf8), httpResponse(request.url!, 503))
        }
        let service = TranscriptCorrectionService(client: mock, maxCharsPerBatch: 1000)
        do {
            _ = try await service.correct("only one batch here")
            XCTFail("Expected an error when all batches fail")
        } catch let error as CorrectionError {
            guard case .httpError(let status, _) = error else {
                return XCTFail("Expected httpError, got \(error)")
            }
            XCTAssertEqual(status, 503)
        } catch {
            XCTFail("Expected CorrectionError, got \(error)")
        }
    }

    // MARK: - Context detection request

    func testDetectContextTokensReturnsNilOnFailure() async {
        let mock = MockHTTPClient { request in
            (Data("nope".utf8), httpResponse(request.url!, 500))
        }
        let service = TranscriptCorrectionService(client: mock)
        let tokens = await service.detectContextTokens()
        XCTAssertNil(tokens)
    }

    func testNativeModelsRequestTargetsApiV0() throws {
        let service = TranscriptCorrectionService(baseURL: "http://localhost:1234/v1", model: "m")
        let request = try service.buildNativeModelsRequest()
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:1234/api/v0/models")
    }

    // MARK: - Response parsing

    func testParseChatContent() throws {
        let data = chatJSON(content: "hello")
        XCTAssertEqual(try TranscriptCorrectionService.parseChatContent(from: data), "hello")
    }

    func testParseChatContentStripsThinkBlock() throws {
        let data = chatJSON(content: "<think>let me reason about this</think>\n⟦SEG:0⟧\nfixed")
        let content = try TranscriptCorrectionService.parseChatContent(from: data)
        XCTAssertFalse(content.contains("<think>"))
        XCTAssertFalse(content.contains("reason"))
        XCTAssertTrue(content.hasPrefix("⟦SEG:0⟧"))
    }

    func testStripReasoningLeavesPlainTextUntouched() {
        XCTAssertEqual(TranscriptCorrectionService.stripReasoning("just text"), "just text")
    }

    func testParseModelIDs() throws {
        let obj: [String: Any] = ["data": [["id": "model-a"], ["id": "model-b"]]]
        let data = try JSONSerialization.data(withJSONObject: obj)
        XCTAssertEqual(try TranscriptCorrectionService.parseModelIDs(from: data), ["model-a", "model-b"])
    }

    // MARK: - End-to-end correction with mock

    func testCorrectAppliesModelOutputWhenSentinelsValid() async throws {
        let mock = MockHTTPClient { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            let messages = body["messages"] as! [[String: String]]
            let userContent = messages.last!["content"]!
            // Echo back the same sentinels with "corrected" text.
            let count = userContent.components(separatedBy: "⟦SEG:").count - 1
            var lines: [String] = []
            for i in 0..<count {
                lines.append(TranscriptCorrectionService.marker(i))
                lines.append("CORRECTED\(i)")
            }
            lines.append(TranscriptCorrectionService.endSentinel)
            return (chatJSON(content: lines.joined(separator: "\n")), httpResponse(request.url!, 200))
        }
        let service = TranscriptCorrectionService(client: mock, maxCharsPerBatch: 1000)
        let result = try await service.correct("para one\npara two")
        XCTAssertEqual(result, "CORRECTED0\n\nCORRECTED1")
    }

    func testCorrectFallsBackToRawWhenSentinelsTampered() async throws {
        let mock = MockHTTPClient { request in
            // Model returns garbage without valid sentinels.
            return (chatJSON(content: "here is my rewrite without markers"), httpResponse(request.url!, 200))
        }
        let service = TranscriptCorrectionService(client: mock, maxCharsPerBatch: 1000)
        let result = try await service.correct("keep me\nand me")
        // Raw preserved, nothing dropped or duplicated.
        XCTAssertEqual(result, "keep me\n\nand me")
    }

    func testCorrectThrowsOnHTTPError() async {
        let mock = MockHTTPClient { request in
            (Data("server on fire".utf8), httpResponse(request.url!, 500))
        }
        let service = TranscriptCorrectionService(client: mock)
        do {
            _ = try await service.correct("something")
            XCTFail("Expected an error")
        } catch let error as CorrectionError {
            guard case .httpError(let status, _) = error else {
                return XCTFail("Expected httpError, got \(error)")
            }
            XCTAssertEqual(status, 500)
        } catch {
            XCTFail("Expected CorrectionError, got \(error)")
        }
    }

    func testCorrectWrapsConnectionFailure() async {
        struct Boom: Error {}
        let mock = MockHTTPClient { _ in throw Boom() }
        let service = TranscriptCorrectionService(client: mock)
        do {
            _ = try await service.correct("x")
            XCTFail("Expected an error")
        } catch let error as CorrectionError {
            guard case .connectionFailed = error else {
                return XCTFail("Expected connectionFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected CorrectionError, got \(error)")
        }
    }

    // MARK: - Request building

    func testChatRequestTargetsChatCompletions() throws {
        let service = TranscriptCorrectionService(baseURL: "http://localhost:1234/v1", model: "m")
        let request = try service.buildChatRequest(userContent: "hi")
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
    }

    func testBaseURLTrailingSlashNormalized() throws {
        let service = TranscriptCorrectionService(baseURL: "http://localhost:1234/v1/", model: "m")
        let request = try service.buildModelsRequest()
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:1234/v1/models")
    }
}
