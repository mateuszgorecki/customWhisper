import XCTest
@testable import CustomWhisper

final class AudioFileDecoderTests: XCTestCase {

    // MARK: - Argument construction

    func testFFmpegArgumentsAreBulletproof() {
        let args = AudioFileDecoder.ffmpegArguments(input: "/tmp/in.ogg", output: "/tmp/out.wav")
        // No stdin, overwrite, first audio stream, mono 16k s16.
        XCTAssertEqual(args.first, "-nostdin")
        XCTAssertTrue(args.contains("-y"))
        XCTAssertEqual(zip(args, args.dropFirst()).first { $0.0 == "-i" }?.1, "/tmp/in.ogg")
        XCTAssertEqual(zip(args, args.dropFirst()).first { $0.0 == "-map" }?.1, "0:a:0")
        XCTAssertEqual(zip(args, args.dropFirst()).first { $0.0 == "-ac" }?.1, "1")
        XCTAssertEqual(zip(args, args.dropFirst()).first { $0.0 == "-ar" }?.1, "16000")
        XCTAssertEqual(zip(args, args.dropFirst()).first { $0.0 == "-c:a" }?.1, "pcm_s16le")
        XCTAssertEqual(args.last, "/tmp/out.wav")
    }

    func testFFprobeArgumentsAskForDurationOnly() {
        let args = AudioFileDecoder.ffprobeArguments(input: "/tmp/in.ogg")
        XCTAssertTrue(args.contains("format=duration"))
        XCTAssertEqual(args.last, "/tmp/in.ogg")
    }

    // MARK: - Duration parsing

    func testParseDurationValid() {
        XCTAssertEqual(AudioFileDecoder.parseDuration(from: "123.456\n"), 123.456)
        XCTAssertEqual(AudioFileDecoder.parseDuration(from: "  0.0  "), 0.0)
    }

    func testParseDurationInvalid() {
        XCTAssertNil(AudioFileDecoder.parseDuration(from: "N/A"))
        XCTAssertNil(AudioFileDecoder.parseDuration(from: ""))
        XCTAssertNil(AudioFileDecoder.parseDuration(from: "-5"))
    }

    // MARK: - Disk footprint estimate

    func testEstimatedTempBytesGrowsWithDuration() {
        let oneHour = AudioFileDecoder.estimatedTempBytes(forDuration: 3600)
        let tenMin = AudioFileDecoder.estimatedTempBytes(forDuration: 600)
        XCTAssertGreaterThan(oneHour, tenMin)
        // One hour should exceed the ~345 MB combined WAV+raw estimate plus margin.
        XCTAssertGreaterThan(oneHour, 300 * 1_024 * 1_024)
    }

    // MARK: - stderr tail

    func testStderrTailKeepsLastLines() {
        let stderr = (1...20).map { "line \($0)" }.joined(separator: "\n")
        let tail = AudioFileDecoder.stderrTail(stderr, maxLines: 3)
        XCTAssertEqual(tail, "line 18\nline 19\nline 20")
    }

    // MARK: - Extension support

    func testSupportedExtensions() {
        XCTAssertTrue(AudioFileDecoder.isSupported(extension: "ogg"))
        XCTAssertTrue(AudioFileDecoder.isSupported(extension: "OGG"))
        XCTAssertTrue(AudioFileDecoder.isSupported(extension: "opus"))
        XCTAssertTrue(AudioFileDecoder.isSupported(extension: "mp3"))
        XCTAssertFalse(AudioFileDecoder.isSupported(extension: "txt"))
        XCTAssertFalse(AudioFileDecoder.isSupported(extension: ""))
    }

    // MARK: - Binary discovery

    func testLocateBinaryFindsInHomebrewPath() {
        let found = AudioFileDecoder.locateBinary(
            "ffmpeg",
            environment: [:],
            fileExists: { $0 == "/opt/homebrew/bin/ffmpeg" }
        )
        XCTAssertEqual(found, "/opt/homebrew/bin/ffmpeg")
    }

    func testLocateBinaryFallsBackToPATH() {
        let found = AudioFileDecoder.locateBinary(
            "ffmpeg",
            environment: ["PATH": "/custom/bin:/other/bin"],
            fileExists: { $0 == "/other/bin/ffmpeg" }
        )
        XCTAssertEqual(found, "/other/bin/ffmpeg")
    }

    func testLocateBinaryReturnsNilWhenMissing() {
        let found = AudioFileDecoder.locateBinary(
            "ffmpeg",
            environment: ["PATH": "/custom/bin"],
            fileExists: { _ in false }
        )
        XCTAssertNil(found)
    }

    // MARK: - Unsupported extension throws

    func testDecodeRejectsUnsupportedExtension() {
        let url = URL(fileURLWithPath: "/tmp/notes.txt")
        XCTAssertThrowsError(try AudioFileDecoder.decode(inputURL: url)) { error in
            guard case AudioFileDecoder.DecoderError.unsupportedExtension = error else {
                return XCTFail("Expected unsupportedExtension, got \(error)")
            }
        }
    }
}
