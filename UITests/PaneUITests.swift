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

    func testDesignPreviewFocusMovesBetweenPanes() {
        let app = XCUIApplication()
        app.launchArguments = ["-designPreview", "dashboard", "-scene", "golden"]
        app.launch()

        let weather = app.buttons["preview.pane.weather"]
        XCTAssertTrue(weather.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocus(weather))

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(app.buttons["preview.pane.github"]))

        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForFocus(app.buttons["preview.pane.home"]))

        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForFocus(app.buttons["preview.pane.forecast"]))
    }

    private func waitForFocus(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "hasFocus == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
