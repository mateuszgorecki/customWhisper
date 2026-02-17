import XCTest
@testable import CustomWhisper

final class TextPasterTests: XCTestCase {

    func testPasteErrorDescription() {
        let error = PasteError.accessibilityNotGranted
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Accessibility"))
    }

    func testIsAvailableReturnsBoolean() {
        // TextPaster.isAvailable just wraps AXIsProcessTrusted().
        // In a test environment this will typically be false.
        let available = TextPaster.isAvailable
        XCTAssertNotNil(available)
    }
}
