import XCTest

/// Gate checks against the real GitHub and Portainer, run only with `TEST_RUNNER_PANE_LIVE_CODE=1`
/// and a signed build (an unsigned one cannot write tokens to the Keychain). The tokens come from
/// the gitignored `local/Secrets.local.xcconfig` through the Debug-only prefill, so this file holds
/// none of them.
@MainActor
final class CodeLiveUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["PANE_LIVE_CODE"] == "1", "Live Code tests are opt-in")
        try Self.requireSecrets()
    }

    func testSetupThroughBothScreensShowsStreakAndCommit() {
        let app = XCUIApplication()
        app.launchArguments = ["-resetSettings", "1", "-settings", "1", "-codeSetup", "prefill", "-nightDim", "off"]
        app.launch()

        let github = cell(app, "settings.code.github")
        XCTAssertTrue(element(app, "settings.code.github").waitForExistence(timeout: 10))
        moveFocus(app, to: github, directions: [.down], limit: 45)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element(app, "code.setup.github.token").waitForExistence(timeout: 5))
        moveFocus(app, to: app.buttons["code.setup.github.test"], directions: [.down], limit: 4)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForLabel(element(app, "code.setup.github.status"), containing: "Connected as", timeout: 30), element(app, "code.setup.github.status").label)
        saveGateShot("live-code-github-connected")
        moveFocus(app, to: app.buttons["code.setup.github.save"], directions: [.down], limit: 2)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForLabel(element(app, "settings.code.github"), containing: "Connected as", timeout: 15), element(app, "settings.code.github").label)

        let portainer = cell(app, "settings.code.portainer")
        moveFocus(app, to: portainer, directions: [.down], limit: 3)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.textFields["code.setup.portainer.address"].waitForExistence(timeout: 5))
        moveFocus(app, to: app.buttons["code.setup.portainer.test"], directions: [.down], limit: 4)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForLabel(element(app, "code.setup.portainer.status"), containing: "Connected", timeout: 30), element(app, "code.setup.portainer.status").label)
        saveGateShot("live-code-portainer-connected")
        moveFocus(app, to: app.buttons["code.setup.portainer.save"], directions: [.down], limit: 2)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForLabel(element(app, "settings.code.portainer"), containing: "Connected", timeout: 15), element(app, "settings.code.portainer").label)
        saveGateShot("live-code-settings")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(element(app, "code.streak").waitForExistence(timeout: 20))
        XCTAssertTrue(element(app, "code.commit").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "code.grid").exists)
        XCTAssertFalse(element(app, "code.warning").exists)
        saveGateShot("live-code-card")
    }

    private static func requireSecrets() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let text = try? String(contentsOf: repo.appendingPathComponent("local/Secrets.local.xcconfig"), encoding: .utf8) else {
            throw XCTSkip("No local/Secrets.local.xcconfig")
        }
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("//") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        for key in ["PANE_GITHUB_TOKEN", "PANE_PORTAINER_HOST", "PANE_PORTAINER_TOKEN", "PANE_PORTAINER_ENDPOINT_ID"] where (values[key] ?? "").isEmpty {
            throw XCTSkip("No \(key) in local secrets")
        }
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

    private func saveGateShot(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["PANE_GATE_SHOTS"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }
}
