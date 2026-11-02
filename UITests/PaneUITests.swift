import XCTest

@MainActor
final class PaneUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testDesignPreviewFocusMovesBetweenPanes() {
        let app = XCUIApplication()
        app.launchArguments = ["-designPreview", "dashboard", "-scene", "golden"]
        app.launch()

        let weather = app.buttons["dashboard.card.current"]
        XCTAssertTrue(weather.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocus(weather))

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(app.buttons["dashboard.card.code"]))

        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForFocus(app.buttons["dashboard.card.home"]))

        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForFocus(app.buttons["dashboard.card.forecast"]))
    }
}
