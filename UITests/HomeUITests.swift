import XCTest

@MainActor
final class HomeUITests: XCTestCase {
    private static let baseArguments = ["-fixtures", "sample", "-nightDim", "off", "-resetSettings", "1", "-now", "2026-11-02T16:12"]

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testCardShowsFixtureRows() {
        let app = launch()
        XCTAssertTrue(waitForValue(element(app, "home.connection"), "connected", timeout: 10))
        for row in ["climate", "humidity", "lock", "lights", "people"] {
            XCTAssertTrue(element(app, "home.row.\(row)").waitForExistence(timeout: 5), "Missing row \(row)")
        }
        XCTAssertFalse(element(app, "home.nudge.dryAir").exists)
        saveGateShot("home-card")
    }

    func testClickingHomeCardOpensScenesAndBackReturns() {
        let app = launch()
        let card = app.buttons["dashboard.card.home"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        moveFocus(app, to: card, directions: [.down, .left])

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element(app, "home.scenes").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(app.buttons["home.scene.scene.sample_goodnight"], timeout: 5), "Focused: \(focusedIdentifier(app))")
        XCTAssertTrue(app.buttons["home.scene.scene.sample_movie"].exists)
        XCTAssertTrue(app.buttons["home.scene.script.sample_morning"].exists)
        saveGateShot("home-scenes")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(element(app, "home.scenes")))
        XCTAssertTrue(waitForFocus(card, timeout: 5), "Focused: \(focusedIdentifier(app))")
    }

    func testScenesOpenFromLaunchOption() {
        let app = launch(["-homeScenes", "1"])
        XCTAssertTrue(waitForFocus(app.buttons["home.scene.scene.sample_goodnight"], timeout: 10))
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForFocus(app.buttons["home.scene.scene.sample_movie"], timeout: 5))
    }

    func testSettingsListsRolesAndPickerShowsFixtureEntities() {
        let app = launch(["-settings", "1"])
        let server = cell(app, "settings.home.server")
        XCTAssertTrue(element(app, "settings.home.server").waitForExistence(timeout: 10))
        moveFocus(app, to: server, directions: [.down], limit: 30)
        saveGateShot("home-settings")
        XCTAssertTrue(element(app, "settings.home.server").label.contains("Connected"), element(app, "settings.home.server").label)

        let thermostat = cell(app, "settings.home.role.thermostat")
        moveFocus(app, to: thermostat, directions: [.down], limit: 3)
        XCTAssertTrue(element(app, "settings.home.role.thermostat").label.contains("Thermostat"))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element(app, "home.picker.row.climate.sample_thermostat").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "home.picker.row.climate.sample_thermostat").value as? String, "selected")
        XCTAssertFalse(element(app, "home.picker.row.sensor.sample_hall_humidity").exists)
        saveGateShot("home-picker-thermostat")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(thermostat, timeout: 5))
    }

    func testMultiSelectPickerTogglesAndKeepsList() {
        let app = launch(["-settings", "1"])
        XCTAssertTrue(element(app, "settings.home.server").waitForExistence(timeout: 10))
        moveFocus(app, to: cell(app, "settings.home.role.lights"), directions: [.down], limit: 30)
        XCUIRemote.shared.press(.select)

        let kitchen = element(app, "home.picker.row.light.sample_kitchen")
        XCTAssertTrue(kitchen.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForFocus(cell(app, "home.picker.row.light.sample_kitchen"), timeout: 5), "Focused: \(focusedIdentifier(app))")
        saveGateShot("home-picker-lights")
        XCTAssertEqual(kitchen.value as? String, "selected")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForValue(kitchen, ""))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForValue(kitchen, "selected"))
    }

    func testNudgeTogglesFlip() {
        let app = launch(["-settings", "1"])
        XCTAssertTrue(element(app, "settings.home.server").waitForExistence(timeout: 10))
        let dry = cell(app, "settings.home.nudge.dryAir")
        moveFocus(app, to: dry, directions: [.down], limit: 30)
        let toggle = element(app, "settings.home.nudge.dryAir")
        let before = toggle.value as? String
        saveGateShot("home-settings-nudges")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForValueChange(toggle, from: before))
    }

    func testSetupScreenShowsFieldsAndKeepsSaveOff() {
        let app = launch(["-settings", "1"])
        XCTAssertTrue(element(app, "settings.home.server").waitForExistence(timeout: 10))
        moveFocus(app, to: cell(app, "settings.home.server"), directions: [.down], limit: 30)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element(app, "home.setup.address").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "home.setup.token").exists)
        XCTAssertFalse(app.buttons["home.setup.save"].isEnabled)
        XCTAssertFalse(app.buttons["home.setup.test"].isEnabled)
        saveGateShot("home-setup")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(element(app, "home.setup.address")))
    }

    func testSetupPrefillFillsFields() throws {
        let app = launch(["-settings", "1", "-homeSetup", "prefill"])
        XCTAssertTrue(element(app, "settings.home.server").waitForExistence(timeout: 10))
        moveFocus(app, to: cell(app, "settings.home.server"), directions: [.down], limit: 30)
        XCUIRemote.shared.press(.select)
        let address = app.textFields["home.setup.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        let value = address.value as? String ?? ""
        try XCTSkipIf(!value.hasPrefix("http"), "No Home Assistant prefill in local/Secrets.local.xcconfig")
        XCTAssertTrue(app.buttons["home.setup.test"].isEnabled)
    }

    /// Waits on the core: needs `testConnection` against the real server.
    func testSetupPrefillTestsAndSaves() throws {
        let app = launch(["-settings", "1", "-homeSetup", "prefill"], fixtures: false)
        XCTAssertTrue(element(app, "settings.home.server").waitForExistence(timeout: 10))
        moveFocus(app, to: cell(app, "settings.home.server"), directions: [.down], limit: 30)
        XCUIRemote.shared.press(.select)
        let address = app.textFields["home.setup.address"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        try XCTSkipIf(!((address.value as? String) ?? "").hasPrefix("http"), "No Home Assistant prefill")

        moveFocus(app, to: app.buttons["home.setup.test"], directions: [.down], limit: 4)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForLabel(element(app, "home.setup.status"), containing: "Connected", timeout: 20), element(app, "home.setup.status").label)
        XCTAssertTrue(app.buttons["home.setup.save"].isEnabled)
        saveGateShot("home-setup-connected")
    }

    /// Waits on the core: nudge rules.
    func testNudgesRaisedByLaunchOverrides() {
        let cases: [(kind: String, extra: [String])] = [
            ("dryAir", []),
            ("humidAir", []),
            ("doorUnlockedLate", ["-now", "2026-11-02T23:10"]),
            ("lightsOnAway", []),
            ("bedroomTVLate", ["-now", "2026-11-03T00:30"]),
        ]
        for entry in cases {
            let app = launch(["-homeNudge", entry.kind] + entry.extra)
            let chip = element(app, "home.nudge.\(entry.kind)")
            XCTAssertTrue(chip.waitForExistence(timeout: 10), "No \(entry.kind) chip")
            saveGateShot("home-nudge-\(entry.kind)")
            pressInDebugHomeRow(app, "debug.home.clear")
            XCTAssertTrue(waitForNonExistence(chip, timeout: 5), "\(entry.kind) chip stayed after its condition cleared")
            app.terminate()
        }
    }

    /// Waits on the core: scene calls and night dim.
    func testGoodnightSceneDimsAndClosesOverlay() {
        let app = launch(["-homeScenes", "1"], pinnedNightDim: false)
        let goodnight = app.buttons["home.scene.scene.sample_goodnight"]
        XCTAssertTrue(waitForFocus(goodnight, timeout: 10))
        XCTAssertTrue(waitForValue(element(app, "dashboard.nightDim"), "off", timeout: 5))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForNonExistence(element(app, "home.scenes"), timeout: 5))
        XCTAssertTrue(waitForValue(element(app, "dashboard.nightDim"), "on", timeout: 5))
    }

    /// Waits on the core: a scene press shows a result line.
    func testOtherSceneShowsResultAndStaysOpen() {
        let app = launch(["-homeScenes", "1"])
        XCTAssertTrue(waitForFocus(app.buttons["home.scene.scene.sample_goodnight"], timeout: 10))
        XCUIRemote.shared.press(.right)
        XCTAssertTrue(waitForFocus(app.buttons["home.scene.scene.sample_movie"], timeout: 5))
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForLabel(element(app, "home.scenes.result"), containing: "Ran Movie", timeout: 5))
        XCTAssertTrue(element(app, "home.scenes").exists)
        saveGateShot("home-scenes-result")
    }

    /// Waits on the core: reconnect.
    func testDroppedConnectionReconnects() {
        let app = launch()
        XCTAssertTrue(waitForValue(element(app, "home.connection"), "connected", timeout: 10))
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.staticTexts["debug.menu"].waitForExistence(timeout: 5))
        focusDebugHomeRow(app, "debug.home.drop")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForValue(element(app, "home.connection"), "disconnected", timeout: 5))
        XCTAssertTrue(waitForValue(element(app, "home.connection"), "connected", timeout: 30))
    }

    private func pressInDebugHomeRow(_ app: XCUIApplication, _ id: String) {
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.staticTexts["debug.menu"].waitForExistence(timeout: 5))
        focusDebugHomeRow(app, id)
        XCUIRemote.shared.press(.select)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(app.staticTexts["debug.menu"]))
    }

    private func focusDebugHomeRow(_ app: XCUIApplication, _ id: String) {
        let homeRow = ["dryAir", "humidAir", "doorUnlockedLate", "lightsOnAway", "bedroomTVLate"].map { app.buttons["debug.home.nudge.\($0)"] }
            + [app.buttons["debug.home.clear"], app.buttons["debug.home.drop"]]
        for _ in 0..<30 where !homeRow.contains(where: \.hasFocus) {
            XCUIRemote.shared.press(.down)
            _ = waitForFocus(app.buttons[id], timeout: 1)
        }
        moveFocus(app, to: app.buttons[id], directions: [.down, .right, .left], limit: 8)
    }

    private func launch(_ extra: [String] = [], fixtures: Bool = true, pinnedNightDim: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = Self.baseArguments
        if !fixtures { arguments.removeSubrange(0..<2) }
        if !pinnedNightDim, let index = arguments.firstIndex(of: "-nightDim") { arguments.removeSubrange(index...(index + 1)) }
        let overridesNow = extra.contains("-now")
        if overridesNow, let index = arguments.firstIndex(of: "-now") { arguments.removeSubrange(index...(index + 1)) }
        app.launchArguments = arguments + extra
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func cell(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.cells.containing(.any, identifier: id).firstMatch
    }

    private func focusedIdentifier(_ app: XCUIApplication) -> String {
        let focused = app.descendants(matching: .any).matching(NSPredicate(format: "hasFocus == true")).firstMatch
        return focused.exists ? "\(focused.elementType.rawValue) \(focused.identifier) \(focused.label)" : "nothing"
    }

    private func moveFocus(_ app: XCUIApplication, to target: XCUIElement, directions: [XCUIRemote.Button], limit: Int = 8) {
        var presses = 0
        while !target.hasFocus, presses < limit {
            for direction in directions where !target.hasFocus && presses < limit {
                XCUIRemote.shared.press(direction)
                presses += 1
                _ = waitForFocus(target, timeout: 1)
            }
        }
        XCTAssertTrue(target.hasFocus, "Focused: \(focusedIdentifier(app))")
    }

    private func waitForValueChange(_ element: XCUIElement, from old: String?, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate { _, _ in (element.value as? String) != old }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed
    }

    private func saveGateShot(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["PANE_GATE_SHOTS"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }
}
