import XCTest

@MainActor
final class CodeUITests: XCTestCase {
    private static let baseArguments = ["-fixtures", "sample", "-nightDim", "off", "-resetSettings", "1", "-now", "2026-11-02T16:12"]

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testCardShowsStreakTodayGridAndCommit() {
        let app = launch()
        XCTAssertTrue(element(app, "code.streak").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "code.today").exists)
        XCTAssertTrue(element(app, "code.grid").exists)
        XCTAssertTrue(element(app, "code.commit").exists)
        XCTAssertTrue(element(app, "code.streak").label.contains("streak"), element(app, "code.streak").label)
        XCTAssertTrue(element(app, "code.today").label.hasSuffix("today"), element(app, "code.today").label)
        XCTAssertTrue(element(app, "code.commit").label.contains("lantern"), element(app, "code.commit").label)
        XCTAssertFalse(element(app, "code.warning").exists)
        saveGateShot("code-card")
    }

    func testNudgeChipShownWhenSampleIsBehind() {
        let app = launch(["-codeNudge", "on"])
        let chip = element(app, "code.nudge")
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        XCTAssertTrue(chip.label.contains("not redeployed"), chip.label)
        saveGateShot("code-nudge-on")
    }

    func testNudgeChipHiddenWhenSampleIsCurrent() {
        let app = launch(["-codeNudge", "off"])
        XCTAssertTrue(element(app, "code.streak").waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "code.nudge").exists)
        saveGateShot("code-nudge-off")
    }

    func testSettingsOpensBothSetupScreensAndBack() {
        let app = launch(["-settings", "1"])
        let github = cell(app, "settings.code.github")
        XCTAssertTrue(element(app, "settings.code.github").waitForExistence(timeout: 10))
        moveFocus(app, to: github, directions: [.down], limit: 45)
        saveGateShot("code-settings")

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element(app, "code.setup.github.token").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["code.setup.github.save"].isEnabled)
        XCTAssertFalse(app.buttons["code.setup.github.test"].isEnabled)
        saveGateShot("code-setup-github")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(element(app, "code.setup.github.token")))
        XCTAssertTrue(waitForFocus(github, timeout: 5), "Focused: \(focusedIdentifier(app))")

        let portainer = cell(app, "settings.code.portainer")
        moveFocus(app, to: portainer, directions: [.down], limit: 3)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element(app, "code.setup.portainer.address").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "code.setup.portainer.environment").exists)
        XCTAssertTrue(element(app, "code.setup.portainer.token").exists)
        XCTAssertFalse(app.buttons["code.setup.portainer.save"].isEnabled)
        XCTAssertFalse(app.buttons["code.setup.portainer.test"].isEnabled)
        saveGateShot("code-setup-portainer")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(element(app, "code.setup.portainer.address")))
        XCTAssertTrue(waitForFocus(portainer, timeout: 5), "Focused: \(focusedIdentifier(app))")
    }

    func testSettingsTogglesFlipAndListTargets() {
        let app = launch(["-settings", "1"])
        XCTAssertTrue(element(app, "settings.code.github").waitForExistence(timeout: 10))
        moveFocus(app, to: cell(app, "settings.code.nudge"), directions: [.down], limit: 45)
        let nudge = element(app, "settings.code.nudge")
        let before = nudge.value as? String
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForValueChange(nudge, from: before))

        let target = cell(app, "settings.code.target.lantern")
        moveFocus(app, to: target, directions: [.down], limit: 3)
        let watch = element(app, "settings.code.target.lantern")
        let watched = watch.value as? String
        saveGateShot("code-settings-targets")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForValueChange(watch, from: watched))
    }

    func testDebugRowNudgeOffHidesTheChip() {
        let app = launch(["-codeNudge", "on"])
        let chip = element(app, "code.nudge")
        XCTAssertTrue(chip.waitForExistence(timeout: 10))

        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.staticTexts["debug.menu"].waitForExistence(timeout: 5))
        focusDebugCodeRow(app, "debug.code.off")
        saveGateShot("debug-code-row")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["debug.code.state"].label.contains("nudges: none"), app.staticTexts["debug.code.state"].label)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(app.staticTexts["debug.menu"]))
        XCTAssertTrue(waitForNonExistence(chip, timeout: 5), "The nudge chip stayed after Nudge off")
    }

    private func focusDebugCodeRow(_ app: XCUIApplication, _ id: String) {
        let codeRow = ["on", "off", "live", "refresh"].map { app.buttons["debug.code.\($0)"] }
        for _ in 0..<40 where !codeRow.contains(where: \.hasFocus) {
            XCUIRemote.shared.press(.down)
            _ = waitForFocus(app.buttons[id], timeout: 1)
        }
        moveFocus(app, to: app.buttons[id], directions: [.down, .right, .left], limit: 8)
    }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Self.baseArguments + extra
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
