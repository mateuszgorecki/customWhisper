import Foundation

/// Writes transcripts to disk as `<name>.txt` (raw) and `<name>.corrected.txt` (corrected)
/// in a user-chosen output folder. Path derivation is pure and testable; file I/O is thin.
enum TranscriptExporter {

    enum ExportError: LocalizedError {
        case writeFailed(String)

        var errorDescription: String? {
            switch self {
            case .writeFailed(let reason):
                return "Could not save transcript file: \(reason)"
            }
        }
    }

    /// Strip the extension and sanitize a source filename into a safe output base name.
    static func baseName(fromSourceFilename filename: String) -> String {
        // Split on "." so a leading-dot name like ".ogg" strips correctly (NSString would not).
        let components = filename.components(separatedBy: ".")
        let stem = components.count >= 2 ? components.dropLast().joined(separator: ".") : filename
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let safe = stem.components(separatedBy: illegal).joined(separator: "-")
        let trimmed = safe.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "transcript" : trimmed
    }

    /// Derive a collision-free file URL. If `<base><suffix>.txt` exists, append `-1`, `-2`, …
    /// `existing` lets tests inject the set of already-present paths.
    static func uniqueURL(in folder: URL,
                          base: String,
                          suffix: String,
                          fileExists: (String) -> Bool) -> URL {
        var candidate = folder.appendingPathComponent("\(base)\(suffix).txt")
        var counter = 1
        while fileExists(candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(counter)\(suffix).txt")
            counter += 1
        }
        return candidate
    }

    // MARK: - Writing

    /// Write the raw transcript. Returns the file path written.
    @discardableResult
    static func writeRaw(_ text: String, sourceFilename: String, to folder: URL) throws -> URL {
        try write(text, sourceFilename: sourceFilename, suffix: "", to: folder)
    }

    /// Write the corrected transcript. Returns the file path written.
    @discardableResult
    static func writeCorrected(_ text: String, sourceFilename: String, to folder: URL) throws -> URL {
        try write(text, sourceFilename: sourceFilename, suffix: ".corrected", to: folder)
    }

    private static func write(_ text: String,
                              sourceFilename: String,
                              suffix: String,
                              to folder: URL) throws -> URL {
        let base = baseName(fromSourceFilename: sourceFilename)
        let url = uniqueURL(in: folder, base: base, suffix: suffix) {
            FileManager.default.fileExists(atPath: $0)
        }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed(error.localizedDescription)
        }
        return url
    }
}
