import Foundation

/// Minimal HTTP surface so the correction service can be unit-tested with a mock.
protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPClient {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// Corrects a raw transcript through LM Studio's OpenAI-compatible API — fixing orthography,
/// punctuation, and mis-recognized words WITHOUT changing meaning, language, or content.
///
/// The transcript is split into paragraph batches; each batch is wrapped in numbered sentinels
/// and the model is asked to return the same structure. If the returned sentinels are missing,
/// reordered, or corrupted, that batch's output is rejected and the RAW text is kept — so the
/// correction can never silently drop, duplicate, or reorder the transcript.
final class TranscriptCorrectionService {

    // MARK: - Config

    private let baseURL: String
    private let model: String
    private let client: HTTPClient
    private let maxCharsPerBatch: Int

    init(baseURL: String = AppConstants.Meeting.defaultLMStudioBaseURL,
         model: String = AppConstants.Meeting.defaultCorrectionModel,
         client: HTTPClient = URLSession.shared,
         maxCharsPerBatch: Int = 4_000) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.model = model
        self.client = client
        self.maxCharsPerBatch = maxCharsPerBatch
    }

    // MARK: - Prompt

    static let systemPrompt = """
    You are a transcript proofreader. Fix spelling, punctuation, capitalization, and obviously \
    mis-recognized words in the user's automatic speech-recognition transcript. Do NOT change the \
    meaning. Do NOT translate or change the language. Do NOT add, remove, summarize, or reorder any \
    content. Preserve every sentinel marker of the form ⟦SEG:n⟧ and the final ⟦END⟧ marker exactly \
    as given, on their own lines, keeping the same order. Return only the corrected text with the \
    markers, nothing else.
    """

    // MARK: - Sentinels (pure, testable)

    static func marker(_ index: Int) -> String { "⟦SEG:\(index)⟧" }
    static let endSentinel = "⟦END⟧"

    /// Wrap a batch of paragraphs into a numbered-sentinel payload for the model.
    static func buildSentinelPayload(_ paragraphs: [String]) -> String {
        var lines: [String] = []
        for (index, paragraph) in paragraphs.enumerated() {
            lines.append(marker(index))
            lines.append(paragraph)
        }
        lines.append(endSentinel)
        return lines.joined(separator: "\n")
    }

    /// Extract corrected paragraphs from a sentinel response. Returns `nil` if any marker is
    /// missing, out of order, or corrupted — the signal to fall back to the raw batch.
    static func parseSentinelResponse(_ response: String, expectedCount: Int) -> [String]? {
        guard expectedCount > 0 else { return [] }
        var results: [String] = []
        var searchStart = response.startIndex

        for index in 0..<expectedCount {
            guard let startRange = response.range(of: marker(index),
                                                  range: searchStart..<response.endIndex) else {
                return nil
            }
            let nextMarker = index + 1 < expectedCount ? marker(index + 1) : endSentinel
            guard let endRange = response.range(of: nextMarker,
                                                range: startRange.upperBound..<response.endIndex) else {
                return nil
            }
            let piece = String(response[startRange.upperBound..<endRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            results.append(piece)
            searchStart = endRange.lowerBound
        }
        return results
    }

    /// Split text into paragraphs, then greedily batch them under `maxChars`.
    static func batchParagraphs(_ text: String, maxChars: Int) -> [[String]] {
        let paragraphs = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else { return [] }

        var batches: [[String]] = []
        var current: [String] = []
        var currentChars = 0

        for paragraph in paragraphs {
            let addition = paragraph.count + 1
            if !current.isEmpty && currentChars + addition > maxChars {
                batches.append(current)
                current = []
                currentChars = 0
            }
            current.append(paragraph)
            currentChars += addition
        }
        if !current.isEmpty { batches.append(current) }
        return batches
    }

    // MARK: - Request building (pure, testable)

    func buildChatRequest(userContent: String) throws -> URLRequest {
        guard let url = URL(string: baseURL + "/chat/completions") else {
            throw CorrectionError.invalidBaseURL(baseURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "stream": false,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": userContent],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    func buildModelsRequest() throws -> URLRequest {
        guard let url = URL(string: baseURL + "/models") else {
            throw CorrectionError.invalidBaseURL(baseURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        return request
    }

    // MARK: - Response parsing (pure, testable)

    static func parseChatContent(from data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw CorrectionError.invalidResponse
        }
        return stripReasoning(content)
    }

    /// Remove `<think>…</think>` chain-of-thought blocks that reasoning models (e.g. Qwen3)
    /// emit inline, which would otherwise pollute the corrected transcript.
    static func stripReasoning(_ text: String) -> String {
        var result = text
        while let start = result.range(of: "<think>"),
              let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
            result.removeSubrange(start.lowerBound..<end.upperBound)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseModelIDs(from data: Data) throws -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else {
            throw CorrectionError.invalidResponse
        }
        return list.compactMap { $0["id"] as? String }
    }

    // MARK: - Public API

    /// List models available on the LM Studio server.
    func availableModels() async throws -> [String] {
        let request = try buildModelsRequest()
        let (data, response) = try await perform(request)
        try Self.validate(response, data: data)
        return try Self.parseModelIDs(from: data)
    }

    /// Correct the full transcript. Emits per-batch progress in `[0, 1]`. Raw text is always
    /// preserved for any batch that fails validation.
    func correct(_ rawText: String,
                 progress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        let batches = Self.batchParagraphs(rawText, maxChars: maxCharsPerBatch)
        guard !batches.isEmpty else { return rawText }

        var correctedParagraphs: [String] = []
        for (batchIndex, batch) in batches.enumerated() {
            let payload = Self.buildSentinelPayload(batch)
            let request = try buildChatRequest(userContent: payload)
            let (data, response) = try await perform(request)
            try Self.validate(response, data: data)
            let content = try Self.parseChatContent(from: data)

            if let parsed = Self.parseSentinelResponse(content, expectedCount: batch.count) {
                // Guard against a batch that returns empty where the raw was not.
                let reconciled = zip(parsed, batch).map { corrected, raw in
                    corrected.isEmpty && !raw.isEmpty ? raw : corrected
                }
                correctedParagraphs.append(contentsOf: reconciled)
            } else {
                // Sentinels tampered / missing / reordered → keep raw for this batch.
                correctedParagraphs.append(contentsOf: batch)
            }

            progress?(Double(batchIndex + 1) / Double(batches.count))
        }

        return correctedParagraphs.joined(separator: "\n\n")
    }

    // MARK: - Networking

    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await client.send(request)
        } catch {
            throw CorrectionError.connectionFailed(error.localizedDescription)
        }
    }

    static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CorrectionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CorrectionError.httpError(status: http.statusCode, body: String(body.prefix(300)))
        }
    }
}

// MARK: - Errors

enum CorrectionError: LocalizedError {
    case invalidBaseURL(String)
    case connectionFailed(String)
    case httpError(status: Int, body: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let url):
            return "Invalid LM Studio URL: \(url)"
        case .connectionFailed(let reason):
            return "Could not reach LM Studio. Is it running with a model loaded? (\(reason))"
        case .httpError(let status, let body):
            return "LM Studio returned an error (HTTP \(status)). \(body)"
        case .invalidResponse:
            return "LM Studio returned an unexpected response."
        }
    }
}
