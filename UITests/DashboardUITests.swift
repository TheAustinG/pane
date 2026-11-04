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

    func testIdleFocusRestsAndAPressBringsItBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-fixtures", "sample", "-nightDim", "off", "-resetSettings", "1"]
        app.launch()
        let weather = app.buttons["dashboard.card.current"]
        let home = app.buttons["dashboard.card.home"]
        XCTAssertTrue(waitForFocus(weather, timeout: 10))
        XCUIRemote.shared.press(.down)
        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForFocus(home))

        XCTAssertTrue(waitForFocus(home, is: false, timeout: 14), "Home card still focused after 10 s idle")
        XCTAssertTrue(waitForFocus(app.buttons["dashboard.rest"], timeout: 2))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dashboard.card.' AND hasFocus == true")).firstMatch.exists)
        saveGateShot("dashboard-resting")

        XCUIRemote.shared.press(.left)
        XCTAssertTrue(waitForFocus(home, timeout: 5), "A press should bring focus back to the last card")
    }

    private func saveGateShot(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["PANE_GATE_SHOTS"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
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
