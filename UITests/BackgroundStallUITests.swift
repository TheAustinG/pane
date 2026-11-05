import XCTest

/// Opening and closing Settings over a photo background, after scene changes in the debug menu,
/// must stay responsive.
@MainActor
final class BackgroundStallUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSettingsOpensAndClosesPromptlyOverAPhoto() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-resetSettings", "1", "-offline", "1", "-nightDim", "off",
            "-background", "photo", "-now", "2026-11-04T12:00",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.card.current"].waitForExistence(timeout: 10))
        let settingsRow = app.descendants(matching: .any).matching(identifier: "settings.background.mode").firstMatch

        for round in 1...4 {
            XCUIRemote.shared.press(.playPause)
            XCTAssertTrue(app.staticTexts["debug.menu"].waitForExistence(timeout: 5))
            XCUIRemote.shared.press(.down)
            XCUIRemote.shared.press(.select)
            XCUIRemote.shared.press(.up)
            XCUIRemote.shared.press(.right)
            XCUIRemote.shared.press(.right)
            XCUIRemote.shared.press(.select)
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(waitForNonExistence(app.staticTexts["debug.menu"]))
            sleep(2)

            let card = app.buttons["dashboard.card.current"]
            for _ in 0..<3 where !card.hasFocus { XCUIRemote.shared.press(.left); _ = waitForFocus(card, timeout: 1) }
            XCUIRemote.shared.press(.up)
            XCTAssertTrue(waitForFocus(app.buttons["dashboard.settings"], timeout: 3), "round \(round): Settings button")
            // A stalled app blocks XCUITest's queries too, so time the step rather than trust the timeout.
            let opened = Date()
            XCUIRemote.shared.press(.select)
            XCTAssertTrue(settingsRow.waitForExistence(timeout: 8))
            let openSeconds = Date().timeIntervalSince(opened)
            XCTAssertLessThan(openSeconds, 6, "round \(round): Settings took \(Int(openSeconds)) s to open")

            let closed = Date()
            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(waitForNonExistence(settingsRow, timeout: 8))
            let closeSeconds = Date().timeIntervalSince(closed)
            XCTAssertLessThan(closeSeconds, 6, "round \(round): Settings took \(Int(closeSeconds)) s to close")
            sleep(2)
        }
    }
}
