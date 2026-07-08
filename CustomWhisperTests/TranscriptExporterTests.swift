import XCTest
@testable import CustomWhisper

final class TranscriptExporterTests: XCTestCase {

    // MARK: - Base name derivation

    func testBaseNameStripsExtension() {
        XCTAssertEqual(TranscriptExporter.baseName(fromSourceFilename: "standup.ogg"), "standup")
        XCTAssertEqual(TranscriptExporter.baseName(fromSourceFilename: "team sync.m4a"), "team sync")
    }

    func testBaseNameSanitizesIllegalCharacters() {
        XCTAssertEqual(TranscriptExporter.baseName(fromSourceFilename: "a/b:c.wav"), "a-b-c")
    }

    func testBaseNameFallsBackWhenEmpty() {
        XCTAssertEqual(TranscriptExporter.baseName(fromSourceFilename: ".ogg"), "transcript")
        XCTAssertEqual(TranscriptExporter.baseName(fromSourceFilename: ""), "transcript")
    }

    // MARK: - Unique URL / collision handling

    func testUniqueURLNoCollision() {
        let folder = URL(fileURLWithPath: "/out")
        let url = TranscriptExporter.uniqueURL(in: folder, base: "meeting", suffix: "", fileExists: { _ in false })
        XCTAssertEqual(url.path, "/out/meeting.txt")
    }

    func testUniqueURLAppendsCounterOnCollision() {
        let folder = URL(fileURLWithPath: "/out")
        let taken: Set<String> = ["/out/meeting.txt", "/out/meeting-1.txt"]
        let url = TranscriptExporter.uniqueURL(in: folder, base: "meeting", suffix: "", fileExists: { taken.contains($0) })
        XCTAssertEqual(url.path, "/out/meeting-2.txt")
    }

    func testCorrectedSuffixURL() {
        let folder = URL(fileURLWithPath: "/out")
        let url = TranscriptExporter.uniqueURL(in: folder, base: "meeting", suffix: ".corrected", fileExists: { _ in false })
        XCTAssertEqual(url.path, "/out/meeting.corrected.txt")
    }

    // MARK: - Actual writes round-trip

    func testWriteRawAndCorrected() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("exporter-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let rawURL = try TranscriptExporter.writeRaw("raw body", sourceFilename: "call.ogg", to: dir)
        let corrURL = try TranscriptExporter.writeCorrected("fixed body", sourceFilename: "call.ogg", to: dir)

        XCTAssertEqual(rawURL.lastPathComponent, "call.txt")
        XCTAssertEqual(corrURL.lastPathComponent, "call.corrected.txt")
        XCTAssertEqual(try String(contentsOf: rawURL, encoding: .utf8), "raw body")
        XCTAssertEqual(try String(contentsOf: corrURL, encoding: .utf8), "fixed body")
    }
}
