import XCTest

/// Photo crossfades and Auto switching on a fixed clock. Gate captures:
/// `TEST_RUNNER_PANE_GATE_SHOTS=<dir>` saves the screen at each step.
@MainActor
final class BackgroundGateUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testConditionChangeCrossfadesThePhoto() {
        let app = launch(["-background", "photo", "-scene", "day", "-now", "2026-11-04T12:00"])
        XCTAssertTrue(waitForValue(kind(app), "photo clear-day", timeout: 10))
        XCTAssertTrue(waitForValue(photoLoaded(app), "yes", timeout: 15))
        saveGateShot("crossfade-1-clear-day")

        openDebugMenu(app)
        XCUIRemote.shared.press(.down)
        let rain = app.buttons["debug.scene.rain"]
        XCTAssertTrue(waitForFocus(rain))
        XCUIRemote.shared.press(.select)
        closeDebugMenu(app)
        XCTAssertTrue(waitForValue(kind(app), "photo rain-day"))
        saveGateShot("crossfade-2-midway")
        XCTAssertTrue(waitForValue(photoLoaded(app), "yes", timeout: 15))
        saveGateShot("crossfade-3-rain-day")
    }

    /// Sunset in Chicago on 2026-11-04 is about 16:35; the reference location is Chicago.
    func testAutoTurnsToTheGradientAfterSunset() {
        let app = launch(["-background", "auto", "-now", "2026-11-04T16:05"])
        XCTAssertTrue(waitForValue(kind(app), "photo clear-dusk", timeout: 10))
        XCTAssertTrue(waitForValue(photoLoaded(app), "yes", timeout: 15))
        saveGateShot("auto-1-before-sunset")

        openDebugMenu(app)
        moveFocus(to: app.buttons["debug.time.minus6h"], pressing: .down, limit: 6)
        moveFocus(to: app.buttons["debug.time.plus1h"], pressing: .right, limit: 6)
        XCUIRemote.shared.press(.select)
        closeDebugMenu(app)
        XCTAssertTrue(waitForValue(kind(app), "gradient"))
        XCTAssertTrue(waitForValue(photoLoaded(app), "no"))
        sleep(7)
        saveGateShot("auto-2-after-sunset")
    }

    func testAutoShowsTheGradientDuringAStormAndThePhotoAfter() {
        let app = launch(["-background", "auto", "-now", "2026-11-04T12:00", "-storm", "storm"])
        XCTAssertTrue(waitForValue(element(app, "dashboard.stormTakeover"), "on", timeout: 10))
        XCTAssertTrue(waitForValue(kind(app), "gradient"))
        saveGateShot("auto-3-storm")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForValue(element(app, "dashboard.stormTakeover"), "off", timeout: 10))
        XCTAssertTrue(waitForValue(kind(app), "photo clear-day"))
        XCTAssertTrue(waitForValue(photoLoaded(app), "yes", timeout: 15))
        saveGateShot("auto-4-after-storm")
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-resetSettings", "1", "-offline", "1", "-nightDim", "off"] + arguments
        app.launch()
        return app
    }

    private func openDebugMenu(_ app: XCUIApplication) {
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.staticTexts["debug.menu"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(app.buttons["debug.scene.live"]))
    }

    private func closeDebugMenu(_ app: XCUIApplication) {
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(app.staticTexts["debug.menu"]))
    }

    private func moveFocus(to target: XCUIElement, pressing direction: XCUIRemote.Button, limit: Int) {
        for _ in 0..<limit where !target.hasFocus {
            XCUIRemote.shared.press(direction)
            _ = waitForFocus(target, timeout: 1)
        }
        XCTAssertTrue(target.hasFocus, "focus never reached \(target.identifier)")
    }

    private func kind(_ app: XCUIApplication) -> XCUIElement { element(app, "background.kind") }

    private func photoLoaded(_ app: XCUIApplication) -> XCUIElement { element(app, "background.photoLoaded") }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func saveGateShot(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["PANE_GATE_SHOTS"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }
}
