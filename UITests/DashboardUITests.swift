import XCTest

@MainActor
final class DashboardUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testLaunchShowsWeatherCard() {
        let app = XCUIApplication()
        app.launch()
        let weather = app.buttons["dashboard.card.current"]
        XCTAssertTrue(weather.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocus(weather))
    }

    func testNightDimFollowsSchedule() {
        let before = XCUIApplication()
        before.launchArguments = ["-resetSettings", "1", "-now", "2026-11-01T22:30"]
        before.launch()
        XCTAssertTrue(nightDim(before).waitForExistence(timeout: 10))
        XCTAssertEqual(nightDim(before).value as? String, "off")
        before.terminate()

        let after = XCUIApplication()
        after.launchArguments = ["-resetSettings", "1", "-now", "2026-11-01T23:30"]
        after.launch()
        XCTAssertTrue(nightDim(after).waitForExistence(timeout: 10))
        XCTAssertEqual(nightDim(after).value as? String, "on")
    }

    func testDebugMenuOpensChoosesSceneAndCloses() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.card.current"].waitForExistence(timeout: 10))

        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.staticTexts["debug.menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(app.buttons["debug.scene.live"]))

        XCUIRemote.shared.press(.down)
        let rain = app.buttons["debug.scene.rain"]
        XCTAssertTrue(waitForFocus(rain))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForValue(rain, "selected"))

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(app.staticTexts["debug.menu"]))
        XCTAssertTrue(waitForFocus(app.buttons["dashboard.card.current"]))
    }

    func testSettingsOpensFromWeatherCardAndMenuReturns() {
        let app = XCUIApplication()
        app.launch()
        let weather = app.buttons["dashboard.card.current"]
        XCTAssertTrue(weather.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForFocus(weather))

        XCUIRemote.shared.press(.up)
        let settings = app.buttons["dashboard.settings"]
        XCTAssertTrue(waitForFocus(settings))

        XCUIRemote.shared.press(.select)
        let nightRow = app.descendants(matching: .any).matching(identifier: "settings.night.enabled").firstMatch
        XCTAssertTrue(nightRow.waitForExistence(timeout: 5), "Settings did not open")
        XCTAssertFalse(weather.hasFocus)

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(settings) || waitForFocus(weather), "Menu did not return to the dashboard")
    }

    private func nightDim(_ app: XCUIApplication) -> XCUIElement {
        app.otherElements["dashboard.nightDim"]
    }
}
