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
    /// Explicit batch size override (chars). `nil` = auto-detect from the model's context window.
    private let maxCharsPerBatch: Int?

    init(baseURL: String = AppConstants.Meeting.defaultLMStudioBaseURL,
         model: String = AppConstants.Meeting.defaultCorrectionModel,
         client: HTTPClient = URLSession.shared,
         maxCharsPerBatch: Int? = nil) {
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.model = model
        self.client = client
        self.maxCharsPerBatch = maxCharsPerBatch
    }

    // MARK: - Batch-size budget (pure, testable)

    /// System prompt + sentinel markers we never spend on transcript text.
    private static let promptReserveTokens = 500
    /// Output can be several times the input for reasoning models (Qwen3 `<think>`),
    /// so we divide the window generously rather than assuming a 1:1 echo.
    private static let echoFactor = 3.0
    /// Conservatively LOW: Polish tokenizes denser than English, so assume fewer
    /// chars per token — underestimating chars means overestimating tokens (safe).
    private static let charsPerToken = 2.0
    private static let budgetSafety = 0.85
    private static let minCharsPerBatch = 800
    /// A model that only reports `max_context_length` (not the loaded window) gets
    /// halved — the runtime window is often far smaller than the max it supports.
    private static let maxContextSafetyFactor = 0.5

    /// Derive a safe per-batch character budget from a model's context window (tokens).
    static func recommendedMaxChars(contextTokens: Int) -> Int {
        let usable = Double(max(0, contextTokens - promptReserveTokens))
        let chars = usable / echoFactor * charsPerToken * budgetSafety
        return max(minCharsPerBatch, Int(chars))
    }

    /// Resolve the effective batch size: explicit override → auto-detected → safe default.
    private func resolveMaxChars() async -> Int {
        if let override = maxCharsPerBatch { return override }
        if let tokens = await detectContextTokens() {
            return Self.recommendedMaxChars(contextTokens: tokens)
        }
        return AppConstants.Meeting.defaultCorrectionMaxChars
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

    /// Break a paragraph longer than `maxChars` into chunks near the limit, cutting on
    /// sentence boundaries first, then words, then hard by character count. Paragraphs at
    /// or under the limit pass through untouched. Guarantees every returned chunk ≤ `maxChars`.
    ///
    /// The ASR transcript arrives as one continuous string with no `\n`, so without this
    /// the whole meeting would land in a single batch and overflow small context windows.
    static func splitLongParagraph(_ text: String, maxChars: Int) -> [String] {
        guard maxChars > 0, text.count > maxChars else { return [text] }

        var chunks: [String] = []
        var current = ""
        for sentence in splitIntoSentences(text) {
            for unit in hardLimited(sentence, maxChars: maxChars) {
                if current.isEmpty {
                    current = unit
                } else if current.count + 1 + unit.count <= maxChars {
                    current += " " + unit
                } else {
                    chunks.append(current)
                    current = unit
                }
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    /// Split on sentence boundaries: after `.`, `!`, or `?` that are followed by whitespace.
    static func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                let next: Character = i + 1 < chars.count ? chars[i + 1] : " "
                if next == " " || next == "\n" || next == "\t" {
                    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { sentences.append(trimmed) }
                    current = ""
                }
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { sentences.append(tail) }
        return sentences
    }

    /// Guarantee a unit fits under `maxChars`: split on spaces, then hard-cut giant words.
    static func hardLimited(_ unit: String, maxChars: Int) -> [String] {
        guard maxChars > 0, unit.count > maxChars else { return [unit] }

        var pieces: [String] = []
        var current = ""
        for word in unit.split(separator: " ", omittingEmptySubsequences: true) {
            let w = String(word)
            if w.count > maxChars {
                if !current.isEmpty { pieces.append(current); current = "" }
                pieces.append(contentsOf: hardCut(w, maxChars: maxChars))
            } else if current.isEmpty {
                current = w
            } else if current.count + 1 + w.count <= maxChars {
                current += " " + w
            } else {
                pieces.append(current)
                current = w
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    /// Last-resort hard split by character count (e.g. a single token longer than the limit).
    static func hardCut(_ s: String, maxChars: Int) -> [String] {
        guard maxChars > 0 else { return [s] }
        var pieces: [String] = []
        var idx = s.startIndex
        while idx < s.endIndex {
            let end = s.index(idx, offsetBy: maxChars, limitedBy: s.endIndex) ?? s.endIndex
            pieces.append(String(s[idx..<end]))
            idx = end
        }
        return pieces
    }

    /// Split text into paragraphs (sub-splitting any that exceed `maxChars`), then greedily
    /// batch them under `maxChars`.
    static func batchParagraphs(_ text: String, maxChars: Int) -> [[String]] {
        let paragraphs = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .flatMap { splitLongParagraph($0, maxChars: maxChars) }

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

        // `max_tokens` is deliberately unset: the model must echo the whole batch back
        // (output ≈ input), and each batch is already sized under the context window, so
        // capping output would risk truncating a valid correction.
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

    /// LM Studio's native REST API (`/api/v0/models`) reports context length per model,
    /// which the OpenAI-compatible `/v1/models` does not. Rooted off the base host.
    func buildNativeModelsRequest() throws -> URLRequest {
        let root = baseURL.hasSuffix("/v1") ? String(baseURL.dropLast(3)) : baseURL
        guard let url = URL(string: root + "/api/v0/models") else {
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

    /// Read the effective context window (tokens) for `model` from a native `/api/v0/models`
    /// payload. Prefers the actually-loaded window; falls back to a discounted `max` when only
    /// the theoretical maximum is known. Returns `nil` if the model or the fields are absent.
    static func parseContextLength(from data: Data, model: String) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]],
              let entry = list.first(where: { ($0["id"] as? String) == model }) else {
            return nil
        }
        if let loaded = entry["loaded_context_length"] as? Int, loaded > 0 {
            return loaded
        }
        if let max = entry["max_context_length"] as? Int, max > 0 {
            return Int(Double(max) * maxContextSafetyFactor)
        }
        return nil
    }

    // MARK: - Public API

    /// List models available on the LM Studio server.
    func availableModels() async throws -> [String] {
        let request = try buildModelsRequest()
        let (data, response) = try await perform(request)
        try Self.validate(response, data: data)
        return try Self.parseModelIDs(from: data)
    }

    /// Best-effort context-window detection for the configured model. Never throws —
    /// any failure (endpoint missing, server down, field absent) returns `nil` so the
    /// caller falls back to a safe default. LM Studio's `/api/v0/models` is beta.
    func detectContextTokens() async -> Int? {
        do {
            let request = try buildNativeModelsRequest()
            let (data, response) = try await client.send(request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else {
                return nil
            }
            return Self.parseContextLength(from: data, model: model)
        } catch {
            return nil
        }
    }

    /// Correct the full transcript. Emits per-batch progress in `[0, 1]`. Raw text is always
    /// preserved for any batch that fails validation.
    func correct(_ rawText: String,
                 progress: (@Sendable (Double) -> Void)? = nil) async throws -> String {
        let maxChars = await resolveMaxChars()
        let batches = Self.batchParagraphs(rawText, maxChars: maxChars)
        guard !batches.isEmpty else { return rawText }

        var correctedParagraphs: [String] = []
        var failedBatches = 0
        var lastError: Error?

        for (batchIndex, batch) in batches.enumerated() {
            do {
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
            } catch {
                // Isolate the failure (e.g. context overflow, timeout): keep raw for this
                // batch and keep going, so one bad batch can't drop the whole correction.
                failedBatches += 1
                lastError = error
                correctedParagraphs.append(contentsOf: batch)
            }

            progress?(Double(batchIndex + 1) / Double(batches.count))
        }

        // Every batch failed to reach the model → surface the error rather than silently
        // returning the untouched raw text (so the UI shows "LM Studio unreachable" etc.).
        if failedBatches == batches.count, let lastError {
            throw lastError
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
