import XCTest

@MainActor
final class SettingsUITests: XCTestCase {
    private static let launchArguments = ["-settings", "1", "-now", "2026-11-01T20:00"]

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testNightRowsExistAndHelpFollowsFocus() {
        let app = launch(reset: true)
        let enabled = element(app, "settings.night.enabled")
        XCTAssertTrue(enabled.waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "settings.night.start").exists)
        XCTAssertTrue(element(app, "settings.night.end").exists)
        XCTAssertTrue(element(app, "settings.night.dimNow").exists)

        XCTAssertTrue(waitForFocus(cell(app, "settings.weather.location")))
        XCTAssertTrue(waitForHelp(app, containing: "Pane has no GPS"))

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(cell(app, "settings.storm.layout")))
        XCTAssertTrue(waitForHelp(app, containing: "weather strip sits when radar takes over"))

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(cell(app, "settings.storm.automatic")))
        XCTAssertTrue(waitForHelp(app, containing: "opens only from the weather card"))

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(cell(app, "settings.background.mode")))
        XCTAssertTrue(waitForHelp(app, containing: "blurred photo of the sky"))

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(cell(app, "settings.background.credits")))
        XCTAssertTrue(waitForHelp(app, containing: "photographer and license"))

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(cell(app, "settings.night.enabled")))
        XCTAssertTrue(waitForHelp(app, containing: "dims to about 30 percent"))

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(cell(app, "settings.night.start")))
        XCTAssertTrue(waitForHelp(app, containing: "dashboard dims for the night"))

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(cell(app, "settings.night.end")))
        XCTAssertTrue(waitForHelp(app, containing: "returns to full brightness"))

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(cell(app, "settings.night.dimNow")))
        XCTAssertTrue(waitForHelp(app, containing: "until the schedule next ends"))
    }

    func testDimNowPersistsAcrossRelaunch() {
        let app = launch(reset: true)
        let dimNow = element(app, "settings.night.dimNow")
        XCTAssertTrue(dimNow.waitForExistence(timeout: 10))
        XCTAssertTrue(dimNow.label.contains("Dim now"), dimNow.label)

        moveFocus(to: cell(app, "settings.night.dimNow"))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForLabel(dimNow, containing: "Brighten now"), dimNow.label)
        XCTAssertTrue(dimNow.label.contains("Dimmed until Mon 6:30 AM"), dimNow.label)
        XCTAssertTrue(waitForHelp(app, containing: "full brightness"))

        app.terminate()
        let relaunched = launch(reset: false)
        let persisted = element(relaunched, "settings.night.dimNow")
        XCTAssertTrue(persisted.waitForExistence(timeout: 10))
        XCTAssertTrue(persisted.label.contains("Brighten now"), persisted.label)

        moveFocus(to: cell(relaunched, "settings.night.dimNow"))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForLabel(persisted, containing: "Dim now"), persisted.label)
    }

    func testStartPickerChangesTheSchedule() {
        let app = launch(reset: true)
        let start = element(app, "settings.night.start")
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        XCTAssertTrue(start.label.contains("11:00 PM"), start.label)

        moveFocus(to: cell(app, "settings.night.start"))
        XCUIRemote.shared.press(.select)
        let current = app.buttons["settings.choice.11:00 PM"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(cell(app, "settings.choice.11:00 PM")))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(cell(app, "settings.choice.11:30 PM")))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForLabel(element(app, "settings.night.start"), containing: "11:30 PM"))
    }

    func testMenuInsideChoiceListReturnsToSettings() {
        let app = launch(reset: true)
        let start = element(app, "settings.night.start")
        XCTAssertTrue(start.waitForExistence(timeout: 10))

        moveFocus(to: cell(app, "settings.night.start"))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["settings.choice.11:00 PM"].waitForExistence(timeout: 5))

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(cell(app, "settings.night.start")))
        XCTAssertTrue(start.label.contains("11:00 PM"), start.label)
    }

    func testMenuDismissesSettings() {
        let app = launch(reset: true)
        let enabled = element(app, "settings.night.enabled")
        XCTAssertTrue(enabled.waitForExistence(timeout: 10))

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(enabled, timeout: 10))
        XCTAssertTrue(app.buttons["dashboard.card.current"].waitForExistence(timeout: 10))
    }

    private func launch(reset: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Self.launchArguments + (reset ? ["-resetSettings", "1"] : [])
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func cell(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.cells.containing(.any, identifier: id).firstMatch
    }

    private func moveFocus(to target: XCUIElement) {
        for _ in 0..<8 where !target.hasFocus {
            XCUIRemote.shared.press(.down)
            _ = waitForFocus(target, timeout: 1)
        }
        XCTAssertTrue(target.hasFocus)
    }

    private func waitForHelp(_ app: XCUIApplication, containing text: String, timeout: TimeInterval = 5) -> Bool {
        waitForLabel(app.staticTexts["settings.help"], containing: text, timeout: timeout)
    }
}
