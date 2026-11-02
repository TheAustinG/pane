import XCTest

@MainActor
final class WeatherUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testOfflineShowsLastDataAndAge() {
        let app = launch([
            "-fixtures", "sample", "-scene", "golden", "-now", "2026-11-01T16:12", "-nightDim", "off",
            "-offline", "1", "-weatherAge", "20", "-resetSettings", "1",
        ])
        let temperature = element(app, "weather.temperature")
        XCTAssertTrue(temperature.waitForExistence(timeout: 10))
        XCTAssertTrue(temperature.label.contains("52°"), temperature.label)
        XCTAssertTrue(waitForLabel(element(app, "weather.freshness"), containing: "Updated 20 min ago", timeout: 10))
        saveGateShot("offline-20min")
    }

    func testEmptyStateAsksForLocation() {
        let app = launch(["-now", "2026-11-01T16:12", "-nightDim", "off", "-offline", "1", "-resetSettings", "1"])
        let empty = element(app, "weather.empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForLabel(empty, containing: "Set your location in Settings"), empty.label)
    }

    func testAttributionQRInSettings() {
        let app = launch(["-settings", "1", "-now", "2026-11-01T20:00", "-offline", "1", "-resetSettings", "1"])
        let row = element(app, "settings.about.attribution")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        moveFocus(to: cell(app, "settings.about.attribution"))
        XCTAssertTrue(waitForLabel(app.staticTexts["settings.help"], containing: "Apple Weather"))
        XCTAssertTrue(element(app, "settings.help.qr").waitForExistence(timeout: 5))
        saveGateShot("settings-attribution")
    }

    func testLocationRowOpensSearchAndBack() {
        let app = launch(["-settings", "1", "-now", "2026-11-01T20:00", "-offline", "1", "-resetSettings", "1"])
        let row = element(app, "settings.weather.location")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.contains("Not set"), row.label)
        XCTAssertTrue(waitForFocus(cell(app, "settings.weather.location")))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element(app, "settings.location.search").waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(cell(app, "settings.weather.location"), timeout: 10))
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
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
        for _ in 0..<10 where !target.hasFocus {
            XCUIRemote.shared.press(.down)
            _ = waitForFocus(target, timeout: 1)
        }
        XCTAssertTrue(target.hasFocus)
    }

    /// Gate captures: `TEST_RUNNER_PANE_GATE_SHOTS=<dir> scripts/ui-test.sh` saves the screen here.
    private func saveGateShot(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["PANE_GATE_SHOTS"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }
}
