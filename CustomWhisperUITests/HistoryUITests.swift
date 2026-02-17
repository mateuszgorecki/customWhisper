import XCTest

final class HistoryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify the main window appears with tabs
        XCTAssertTrue(app.windows.count >= 1)
    }

    func testSettingsTabExists() throws {
        let app = XCUIApplication()
        app.launch()

        let settingsTab = app.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
    }

    func testHistoryTabExists() throws {
        let app = XCUIApplication()
        app.launch()

        let historyTab = app.buttons["History"]
        XCTAssertTrue(historyTab.waitForExistence(timeout: 5))
    }
}
