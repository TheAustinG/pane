import XCTest

@MainActor
final class PaneUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testLaunchShowsPlaceholder() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["pane.placeholder"].waitForExistence(timeout: 10))
    }
}
