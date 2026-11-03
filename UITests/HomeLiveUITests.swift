import XCTest

/// Gate checks against the real Home Assistant. The server and token come from the gitignored
/// `local/Secrets.local.xcconfig` at run time, so these skip anywhere it is missing. They touch only
/// the test helpers: the `input_boolean.pane_test` toggle and the script named "Pane test". Run them
/// in name order: the first one completes setup and picks the entities the others rely on.
@MainActor
final class HomeLiveUITests: XCTestCase {
    private static let helperToggle = "input_boolean.pane_test"
    private static let helperScriptName = "Pane test"

    private var server: LiveServer!

    override func setUp() async throws {
        continueAfterFailure = false
        server = try LiveServer.load()
    }

    func test1SetupThroughTheScreenAndPickEntities() async throws {
        let app = launch(["-resetSettings", "1", "-settings", "1", "-homeSetup", "prefill"])
        XCTAssertTrue(element(app, "settings.home.server").waitForExistence(timeout: 10))
        moveFocus(app, to: cell(app, "settings.home.server"), directions: [.down], limit: 30)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.textFields["home.setup.address"].waitForExistence(timeout: 5))
        moveFocus(app, to: app.buttons["home.setup.test"], directions: [.down], limit: 4)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForLabel(element(app, "home.setup.status"), containing: "Connected", timeout: 20), element(app, "home.setup.status").label)
        moveFocus(app, to: app.buttons["home.setup.save"], directions: [.down], limit: 2)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForLabel(element(app, "settings.home.server"), containing: "Connected", timeout: 15))

        pickFirst(app, role: "thermostat")
        pickAll(app, role: "humidity")
        pickFirst(app, role: "lock")
        pickAll(app, role: "lights", shot: "live-picker-lights")
        pickAll(app, role: "people")
        pickMatching(app, role: "scenes", label: Self.helperScriptName)

        moveFocus(app, to: cell(app, "settings.home.goodnight"), directions: [.down], limit: 4)
        XCUIRemote.shared.press(.select)
        let choice = app.buttons["settings.choice.\(Self.helperScriptName)"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        moveFocus(app, to: choice, directions: [.down], limit: 3)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForLabel(element(app, "settings.home.goodnight"), containing: Self.helperScriptName, timeout: 5))
        saveGateShot("live-settings")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForValue(element(app, "home.connection"), "connected", timeout: 10))
        saveGateShot("live-card")
    }

    func test2CardFollowsTheHelperWithinTwoSeconds() async throws {
        let app = launch()
        let lights = element(app, "home.row.lights")
        XCTAssertTrue(waitForValue(element(app, "home.connection"), "connected", timeout: 15))
        XCTAssertTrue(lights.waitForExistence(timeout: 5))
        let start = try await server.state(of: Self.helperToggle)
        for round in 1...2 {
            let before = rowText(lights)
            let sent = Date()
            try await server.call("input_boolean", "toggle", entityID: Self.helperToggle)
            let seconds = secondsUntil(timeout: 5) { self.rowText(lights) != before }
            let elapsed = seconds.map { _ in Date().timeIntervalSince(sent) }
            print("live toggle round \(round): card changed after \(elapsed.map { String(format: "%.2f", $0) } ?? "never") s")
            XCTAssertNotNil(elapsed, "Card did not change after toggling the helper")
            XCTAssertLessThan(elapsed ?? 99, 2)
            if round == 1 { saveGateShot("live-card-toggled") }
        }
        let end = try await server.state(of: Self.helperToggle)
        XCTAssertEqual(start, end, "The helper should end where it started")
    }

    func test3SceneButtonRunsTheTestScriptAndDims() async throws {
        let app = launch(["-homeScenes", "1"], pinnedNightDim: false)
        let script = try await server.entityID(domain: "script", named: Self.helperScriptName)
        let before = try await server.attribute("last_triggered", of: script)
        let button = app.buttons["home.scene.\(script)"]
        XCTAssertTrue(waitForFocus(button, timeout: 15), "Focused: \(focusedIdentifier(app))")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.scene.'")).count == 1, "Only the test script may be a scene button here")
        if (element(app, "dashboard.nightDim").value as? String) == "on" {
            scrubBackSixHours(app)
            XCTAssertTrue(waitForFocus(button, timeout: 10), "Focused: \(focusedIdentifier(app))")
        }
        XCTAssertTrue(waitForValue(element(app, "dashboard.nightDim"), "off", timeout: 5))
        saveGateShot("live-scenes")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForValue(element(app, "dashboard.nightDim"), "on", timeout: 10))
        let after = try await server.attribute("last_triggered", of: script)
        print("live script last_triggered \(before ?? "nil") -> \(after ?? "nil")")
        XCTAssertNotEqual(before, after, "The test script did not run")
        saveGateShot("live-goodnight-dimmed")
    }

    func test4DroppedSocketReconnectsWithinThirtySeconds() {
        let app = launch()
        let connection = element(app, "home.connection")
        XCTAssertTrue(waitForValue(connection, "connected", timeout: 15))
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.staticTexts["debug.menu"].waitForExistence(timeout: 5))
        let drop = app.buttons["debug.home.drop"]
        let homeRow = ["dryAir", "humidAir", "doorUnlockedLate", "lightsOnAway", "bedroomTVLate"].map { app.buttons["debug.home.nudge.\($0)"] }
            + [app.buttons["debug.home.clear"], drop]
        for _ in 0..<30 where !homeRow.contains(where: \.hasFocus) {
            XCUIRemote.shared.press(.down)
            _ = waitForFocus(drop, timeout: 1)
        }
        moveFocus(app, to: drop, directions: [.down, .right, .left], limit: 8)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForValue(connection, "disconnected", timeout: 5))
        let dropped = Date()
        XCTAssertTrue(waitForValue(connection, "connected", timeout: 30))
        print("live reconnect after \(String(format: "%.1f", Date().timeIntervalSince(dropped))) s")
        XCUIRemote.shared.press(.menu)
    }

    /// The night schedule dims the dashboard late in the evening, which would hide whether the
    /// scene button dimmed it. Six hours back lands outside the window.
    private func scrubBackSixHours(_ app: XCUIApplication) {
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.staticTexts["debug.menu"].waitForExistence(timeout: 5))
        let back = app.buttons["debug.time.minus6h"]
        moveFocus(app, to: back, directions: [.down, .left], limit: 12)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForValue(element(app, "dashboard.nightDim"), "off", timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(app.staticTexts["debug.menu"]))
    }

    private func pickFirst(_ app: XCUIApplication, role: String) {
        openPicker(app, role: role)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForNonExistence(element(app, "home.picker.\(role)")))
    }

    private func pickAll(_ app: XCUIApplication, role: String, shot: String? = nil) {
        openPicker(app, role: role)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.picker.row.'"))
        let count = rows.count
        for index in 0..<count {
            let row = rows.element(boundBy: index)
            moveFocus(app, to: row, directions: [.down], limit: count)
            if row.value as? String != "selected" {
                XCUIRemote.shared.press(.select)
                XCTAssertTrue(waitForValue(row, "selected"))
            }
        }
        if let shot { saveGateShot(shot) }
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(element(app, "home.picker.\(role)")))
    }

    private func pickMatching(_ app: XCUIApplication, role: String, label: String) {
        openPicker(app, role: role)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home.picker.row.' AND label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        moveFocus(app, to: row, directions: [.down], limit: 20)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForValue(row, "selected"))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(element(app, "home.picker.\(role)")))
    }

    private func openPicker(_ app: XCUIApplication, role: String) {
        moveFocus(app, to: cell(app, "settings.home.role.\(role)"), directions: [.down], limit: 10)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(element(app, "home.picker.\(role)").waitForExistence(timeout: 5))
    }

    private func rowText(_ row: XCUIElement) -> String {
        row.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "|")
    }

    private func secondsUntil(timeout: TimeInterval, _ condition: () -> Bool) -> TimeInterval? {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if condition() { return Date().timeIntervalSince(start) }
        }
        return nil
    }

    private func launch(_ extra: [String] = [], pinnedNightDim: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = (pinnedNightDim ? ["-nightDim", "off"] : []) + extra
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
        return focused.exists ? "\(focused.identifier) \(focused.label)" : "nothing"
    }

    private func moveFocus(_ app: XCUIApplication, to target: XCUIElement, directions: [XCUIRemote.Button], limit: Int) {
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

/// Home Assistant's REST API, for the test to change and read the helpers on the same clock it
/// watches the screen with.
private struct LiveServer {
    let base: URL
    let token: String

    static func load() throws -> LiveServer {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        guard let text = try? String(contentsOf: repo.appendingPathComponent("local/Secrets.local.xcconfig"), encoding: .utf8) else {
            throw XCTSkip("No local/Secrets.local.xcconfig")
        }
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") where !line.hasPrefix("//") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { values[parts[0]] = parts[1] }
        }
        guard let host = values["PANE_HA_HOST"], !host.isEmpty,
              let token = values["PANE_HA_TOKEN"], !token.isEmpty else { throw XCTSkip("No Home Assistant in local secrets") }
        let scheme = values["PANE_HA_SCHEME"] == "https" ? "https" : "http"
        guard let base = URL(string: "\(scheme)://\(host)") else { throw XCTSkip("Bad Home Assistant host") }
        return LiveServer(base: base, token: token)
    }

    func state(of entityID: String) async throws -> String {
        try await json("api/states/\(entityID)")["state"] as? String ?? ""
    }

    func attribute(_ name: String, of entityID: String) async throws -> String? {
        (try await json("api/states/\(entityID)")["attributes"] as? [String: Any])?[name] as? String
    }

    func entityID(domain: String, named name: String) async throws -> String {
        let states = try await request("api/states") as? [[String: Any]] ?? []
        let match = states.first { state in
            let id = state["entity_id"] as? String ?? ""
            let friendly = (state["attributes"] as? [String: Any])?["friendly_name"] as? String
            return id.hasPrefix("\(domain).") && friendly == name
        }
        guard let id = match?["entity_id"] as? String else { throw XCTSkip("No \(domain) named \(name)") }
        return id
    }

    func call(_ domain: String, _ service: String, entityID: String) async throws {
        _ = try await request("api/services/\(domain)/\(service)", body: ["entity_id": entityID])
    }

    private func json(_ path: String) async throws -> [String: Any] {
        try await request(path) as? [String: Any] ?? [:]
    }

    private func request(_ path: String, body: [String: Any]? = nil) async throws -> Any {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200 else { throw URLError(.badServerResponse, userInfo: ["status": status]) }
        return try JSONSerialization.jsonObject(with: data)
    }
}
