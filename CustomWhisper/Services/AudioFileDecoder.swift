import Foundation

/// Decodes an arbitrary audio file to the 16 kHz mono PCM WAV that FluidAudio expects,
/// using the system `ffmpeg`. AVFoundation cannot read Ogg/Opus natively, so we shell out.
///
/// Mitigations baked in (from the inversion review):
/// - The selected input is first COPIED into an app-owned per-job temp dir; ffmpeg only ever
///   reads that copy, so TCC access attribution never has to cross into the child process.
/// - `ffprobe` preflight reads duration and refuses jobs whose estimated temp footprint would
///   exceed free disk space.
/// - All temp artifacts for one job live under a single job dir; a static sweep removes orphans
///   left behind by a crash/kill at launch.
enum AudioFileDecoder {

    // MARK: - Result

    struct DecodedAudio {
        /// 16 kHz mono s16 WAV, ready for FluidAudio.
        let wavURL: URL
        /// Duration in seconds, read from ffprobe (authoritative — do NOT trust ASRResult.duration).
        let duration: TimeInterval
        /// The per-job temp directory owning `wavURL` and the input copy. Delete when done.
        let jobDirectory: URL
    }

    // MARK: - Errors

    enum DecoderError: LocalizedError {
        case ffmpegNotFound
        case ffprobeNotFound
        case unsupportedExtension(String)
        case probeFailed(String)
        case insufficientDiskSpace(requiredBytes: Int, availableBytes: Int)
        case decodeFailed(stderrTail: String)
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "ffmpeg was not found. Install it with `brew install ffmpeg` and try again."
            case .ffprobeNotFound:
                return "ffprobe was not found. Install ffmpeg with `brew install ffmpeg` and try again."
            case .unsupportedExtension(let ext):
                return "Unsupported audio format \".\(ext)\". Supported: \(AppConstants.Meeting.acceptedExtensions.map { ".\($0)" }.joined(separator: " "))."
            case .probeFailed(let reason):
                return "Could not read audio file metadata: \(reason)"
            case .insufficientDiskSpace(let required, let available):
                let req = ByteCountFormatter.string(fromByteCount: Int64(required), countStyle: .file)
                let avail = ByteCountFormatter.string(fromByteCount: Int64(available), countStyle: .file)
                return "Not enough free disk space to transcribe this file (needs ~\(req), \(avail) available)."
            case .decodeFailed(let tail):
                return "Audio decoding failed.\n\(tail)"
            case .copyFailed(let reason):
                return "Could not stage the input file for decoding: \(reason)"
            }
        }
    }

    // MARK: - Binary discovery

    private static let searchPaths = ["/opt/homebrew/bin", "/usr/local/bin"]

    /// Locate a tool by name in the known Homebrew paths, then in PATH. `nil` if not found.
    static func locateBinary(_ name: String,
                             environment: [String: String] = ProcessInfo.processInfo.environment,
                             fileExists: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> String? {
        for dir in searchPaths {
            let candidate = "\(dir)/\(name)"
            if fileExists(candidate) { return candidate }
        }
        if let pathVar = environment["PATH"] {
            for dir in pathVar.split(separator: ":") {
                let candidate = "\(dir)/\(name)"
                if fileExists(candidate) { return candidate }
            }
        }
        return nil
    }

    // MARK: - Pure argument builders (testable)

    /// The bullet-proof ffmpeg argument list: no stdin, overwrite output, first audio stream only,
    /// downmix to mono 16 kHz signed-16 PCM WAV.
    static func ffmpegArguments(input: String, output: String) -> [String] {
        [
            "-nostdin",
            "-y",
            "-i", input,
            "-map", "0:a:0",
            "-ac", "1",
            "-ar", "16000",
            "-c:a", "pcm_s16le",
            output,
        ]
    }

    static func ffprobeArguments(input: String) -> [String] {
        [
            "-v", "error",
            "-show_entries", "format=duration",
            "-of", "default=noprint_wrappers=1:nokey=1",
            input,
        ]
    }

    // MARK: - Pure parsers (testable)

    /// Parse ffprobe's `format=duration` output (a bare float in seconds). `nil` if unparseable.
    static func parseDuration(from ffprobeOutput: String) -> TimeInterval? {
        let trimmed = ffprobeOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Estimated peak temp footprint for a clip of the given duration (WAV + FluidAudio raw float).
    static func estimatedTempBytes(forDuration duration: TimeInterval) -> Int {
        let seconds = max(duration, 0)
        let wav = Int(seconds) * AppConstants.Meeting.estimatedWavBytesPerSecond
        let raw = Int(seconds) * AppConstants.Meeting.estimatedRawFloatBytesPerSecond
        return wav + raw + AppConstants.Meeting.freeSpaceSafetyMarginBytes
    }

    /// Keep only the last `maxLines` lines of stderr for a compact, useful error message.
    static func stderrTail(_ stderr: String, maxLines: Int = 8) -> String {
        let lines = stderr.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.suffix(maxLines).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isSupported(extension ext: String) -> Bool {
        AppConstants.Meeting.acceptedExtensions.contains(ext.lowercased())
    }

    // MARK: - Temp directory management

    /// Root under which every job's temp dir is created, so orphans are easy to find and sweep.
    static var tempRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("CustomWhisperMeetings", isDirectory: true)
    }

    static func makeJobDirectory() throws -> URL {
        let dir = tempRoot.appendingPathComponent("job-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func cleanupJob(_ jobDirectory: URL) {
        try? FileManager.default.removeItem(at: jobDirectory)
    }

    /// Delete every job temp dir left behind by a previous run. Call once at launch.
    static func sweepOrphanedJobs() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil) else {
            return
        }
        for entry in entries where entry.lastPathComponent.hasPrefix("job-") {
            try? fm.removeItem(at: entry)
        }
    }

    // MARK: - Self-check

    /// Run `ffmpeg -version` to surface a concrete spawn/exec failure early. Throws on any problem.
    static func verifyFFmpegAvailable() throws {
        guard let ffmpeg = locateBinary("ffmpeg") else { throw DecoderError.ffmpegNotFound }
        let result = try runProcess(executable: ffmpeg, arguments: ["-version"])
        guard result.exitCode == 0 else {
            throw DecoderError.decodeFailed(stderrTail: stderrTail(result.stderr))
        }
    }

    // MARK: - Main entry point

    /// Copy → probe → preflight → decode. Returns the WAV, its ffprobe duration, and the job dir
    /// (which the caller must `cleanupJob` once transcription finishes or fails).
    static func decode(inputURL: URL) throws -> DecodedAudio {
        let ext = inputURL.pathExtension.lowercased()
        guard isSupported(extension: ext) else {
            throw DecoderError.unsupportedExtension(ext)
        }
        guard let ffmpeg = locateBinary("ffmpeg") else { throw DecoderError.ffmpegNotFound }
        guard let ffprobe = locateBinary("ffprobe") else { throw DecoderError.ffprobeNotFound }

        let jobDir = try makeJobDirectory()

        do {
            // 1. Stage a copy the child process is guaranteed to be allowed to read.
            let inputCopy = jobDir.appendingPathComponent("input.\(ext)")
            do {
                try FileManager.default.copyItem(at: inputURL, to: inputCopy)
            } catch {
                throw DecoderError.copyFailed(error.localizedDescription)
            }

            // 2. Probe duration.
            let probe = try runProcess(executable: ffprobe, arguments: ffprobeArguments(input: inputCopy.path))
            guard probe.exitCode == 0, let duration = parseDuration(from: probe.stdout) else {
                throw DecoderError.probeFailed(stderrTail(probe.stderr))
            }

            // 3. Preflight free space.
            let required = estimatedTempBytes(forDuration: duration)
            if let available = availableCapacityBytes(at: jobDir), available < required {
                throw DecoderError.insufficientDiskSpace(requiredBytes: required, availableBytes: available)
            }

            // 4. Decode to WAV.
            let wavURL = jobDir.appendingPathComponent("audio16k.wav")
            let decode = try runProcess(
                executable: ffmpeg,
                arguments: ffmpegArguments(input: inputCopy.path, output: wavURL.path)
            )
            guard decode.exitCode == 0, FileManager.default.fileExists(atPath: wavURL.path) else {
                throw DecoderError.decodeFailed(stderrTail: stderrTail(decode.stderr))
            }

            return DecodedAudio(wavURL: wavURL, duration: duration, jobDirectory: jobDir)
        } catch {
            cleanupJob(jobDir)
            throw error
        }
    }

    // MARK: - Process helper

    struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    static func runProcess(executable: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return ProcessResult(
            exitCode: process.terminationStatus,
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? ""
        )
    }

    private static func availableCapacityBytes(at url: URL) -> Int? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let capacity = values.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return Int(capacity)
    }
}
