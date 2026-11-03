import XCTest

@MainActor
final class StormUITests: XCTestCase {
    /// Pinned two days back, so the storm sample's rain chances never line up with the real clock
    /// that storm mode reads.
    private static let baseArguments = ["-fixtures", "sample", "-scene", "storm", "-nightDim", "off", "-resetSettings", "1"]
    private static let pinnedNow = ["-now", "2026-11-01T19:05"]

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testSimulatedStormTakesOverAndClears() {
        let app = launch()
        XCTAssertTrue(waitForFocus(app.buttons["dashboard.card.current"], timeout: 10))
        XCTAssertEqual(takeover(app).value as? String, "off")

        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.staticTexts["debug.menu"].waitForExistence(timeout: 5))
        moveFocusInStormRow(app, to: "debug.storm.storm")
        XCUIRemote.shared.press(.select)
        let appeared = secondsUntil(takeover(app), is: "on")
        XCTAssertNotNil(appeared, "No takeover within 1 s")
        print("takeover appeared after \(appeared ?? -1) s")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(app.staticTexts["debug.menu"]))
        XCTAssertTrue(waitForFocus(element(app, "storm.timeline"), timeout: 5))
        saveGateShot("storm-simulated")

        XCUIRemote.shared.press(.playPause)
        moveFocusInStormRow(app, to: "debug.storm.clear")
        XCUIRemote.shared.press(.select)
        let cleared = secondsUntil(takeover(app), is: "off")
        XCTAssertNotNil(cleared, "Takeover still up 1 s after clearing")
        print("takeover cleared after \(cleared ?? -1) s")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(app.buttons["dashboard.card.current"], timeout: 5))
    }

    func testWeatherCardOpensRadarAndBackReturns() {
        let app = launch()
        let card = app.buttons["dashboard.card.current"]
        XCTAssertTrue(waitForFocus(card, timeout: 10))

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForValue(takeover(app), "on", timeout: 2))
        XCTAssertTrue(waitForFocus(element(app, "storm.timeline"), timeout: 5))
        saveGateShot("radar-on-demand")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForValue(takeover(app), "off", timeout: 2))
        XCTAssertTrue(waitForFocus(card, timeout: 5))
    }

    func testAlertShowsIssuedTextAndQR() {
        for layout in ["side", "bottom"] {
            let app = launch(["-storm", "alert", "-stormLayout", layout])
            XCTAssertTrue(waitForValue(takeover(app), "on", timeout: 10))
            let title = element(app, "storm.alert.0.title")
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            XCTAssertEqual(title.label, "Severe Thunderstorm Warning")
            XCTAssertTrue(element(app, "storm.alert.0.qr").exists)
            XCTAssertTrue(waitForFocus(app.buttons["storm.alert.0"], timeout: 5))
            saveGateShot("storm-alert-\(layout)")

            XCUIRemote.shared.press(.select)
            XCTAssertTrue(element(app, "storm.alertDetail").waitForExistence(timeout: 5))
            XCTAssertTrue(element(app, "storm.alertDetail.qr.0").exists)
            saveGateShot("storm-alert-detail-\(layout)")

            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(waitForNonExistence(element(app, "storm.alertDetail")))
            XCTAssertEqual(takeover(app).value as? String, "on")

            XCUIRemote.shared.press(.menu)
            XCTAssertTrue(waitForValue(takeover(app), "off", timeout: 2))
            app.terminate()
        }
    }

    func testBackDismissesStorm() {
        let app = launch(["-storm", "storm"])
        XCTAssertTrue(waitForValue(takeover(app), "on", timeout: 10))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForValue(takeover(app), "off", timeout: 2))
        XCTAssertTrue(waitForFocus(app.buttons["dashboard.card.current"], timeout: 5))
    }

    /// The storm sample laid out around the real clock has a 90 percent chance this hour.
    func testRainChanceTakesOverUnlessAutomaticIsOff() {
        let app = launch(pinned: false)
        XCTAssertTrue(waitForValue(takeover(app), "on", timeout: 10))
        app.terminate()

        let settings = launch(["-settings", "1"], pinned: false)
        let automatic = element(settings, "settings.storm.automatic")
        XCTAssertTrue(automatic.waitForExistence(timeout: 10))
        moveFocus(to: settings.cells.containing(.any, identifier: "settings.storm.automatic").firstMatch)
        let before = automatic.value as? String
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(wait(until: { (automatic.value as? String) != before }), "Automatic takeover did not toggle")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(settings.buttons["dashboard.card.current"], timeout: 5))
        XCTAssertEqual(takeover(settings).value as? String, "off")
    }

    private func launch(_ extra: [String] = [], pinned: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Self.baseArguments + (pinned ? Self.pinnedNow : []) + extra
        app.launch()
        return app
    }

    private func takeover(_ app: XCUIApplication) -> XCUIElement {
        app.otherElements["dashboard.stormTakeover"]
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    /// `XCTNSPredicateExpectation` polls about once a second, too coarse for a 1 s limit. Each
    /// query here takes a snapshot, so the time measured includes XCUITest's own latency.
    private func secondsUntil(_ element: XCUIElement, is value: String, limit: TimeInterval = 1) -> TimeInterval? {
        let start = Date.now
        while Date.now.timeIntervalSince(start) < limit {
            if element.value as? String == value { return Date.now.timeIntervalSince(start) }
        }
        return nil
    }

    private func wait(until condition: @escaping () -> Bool, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate { _, _ in condition() }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed
    }

    /// Down reaches the storm row at whichever button sits under the one above, so finish sideways.
    private func moveFocusInStormRow(_ app: XCUIApplication, to id: String) {
        let row = ["debug.storm.storm", "debug.storm.alert", "debug.storm.clear"].map { app.buttons[$0] }
        for _ in 0..<12 where !row.contains(where: \.hasFocus) {
            XCUIRemote.shared.press(.down)
            _ = wait(until: { row.contains(where: \.hasFocus) }, timeout: 1)
        }
        let target = app.buttons[id]
        for direction in [XCUIRemote.Button.left, .right] {
            for _ in 0..<3 where !target.hasFocus {
                XCUIRemote.shared.press(direction)
                _ = waitForFocus(target, timeout: 1)
            }
        }
        XCTAssertTrue(target.hasFocus)
    }

    private func moveFocus(to target: XCUIElement) {
        for _ in 0..<12 where !target.hasFocus {
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
