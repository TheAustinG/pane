import XCTest

@MainActor
final class BackgroundUITests: XCTestCase {
    private static let midday = "2026-11-01T12:00"
    private static let night = "2026-11-01T23:00"

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testPreviewFollowsFocusAndBackReverts() {
        let app = launch(stored: "gradient", now: Self.midday)
        let preview = element(app, "settings.background.preview")
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValue(preview, "gradient"))

        openChoiceScreen(app)
        XCTAssertTrue(waitForValue(preview, "gradient"))
        attachScreenshot("settings-background-choice")

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(cell(app, "settings.background.option.photo")))
        XCTAssertTrue(waitForValue(preview, "photo"))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(cell(app, "settings.background.option.auto")))
        XCTAssertTrue(waitForValue(preview, "auto"))
        XCUIRemote.shared.press(.up)
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(waitForFocus(cell(app, "settings.background.option.gradient")))
        XCTAssertTrue(waitForValue(preview, "gradient"))

        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForValue(preview, "photo"))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(app.buttons["settings.background.option.photo"]))
        XCTAssertTrue(waitForValue(preview, "gradient"))
        XCTAssertTrue(waitForLabel(element(app, "settings.background.mode"), containing: "Gradient"))
    }

    /// Waits on `BackgroundPolicy` returning `.photo` for the photo mode.
    func testBackdropKindFollowsPreviewAndRevertsOnBack() {
        let app = launch(stored: "gradient", now: Self.midday)
        let kind = element(app, "background.kind")
        XCTAssertTrue(kind.waitForExistence(timeout: 10))
        XCTAssertTrue(waitForValue(kind, "gradient"))

        openChoiceScreen(app)
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForFocus(cell(app, "settings.background.option.photo")))
        XCTAssertTrue(waitForKind(kind, startingWith: "photo"), "\(kind.value ?? "nil")")

        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForNonExistence(app.buttons["settings.background.option.photo"]))
        XCTAssertTrue(waitForValue(kind, "gradient"))
    }

    func testSelectingGradientShowsGradient() {
        let app = launch(stored: "photo", now: Self.midday)
        choose("gradient", in: app)
        XCTAssertTrue(waitForLabel(element(app, "settings.background.mode"), containing: "Gradient"))
        let kind = dashboardKind(app)
        XCTAssertTrue(waitForValue(kind, "gradient"), "\(kind.value ?? "nil")")
        attachScreenshot("background-gradient")
    }

    /// Waits on `BackgroundPolicy` returning `.photo` for the photo mode.
    func testSelectingPhotoShowsPhoto() {
        let app = launch(stored: "gradient", now: Self.midday)
        choose("photo", in: app)
        XCTAssertTrue(waitForLabel(element(app, "settings.background.mode"), containing: "Photo"))
        let kind = dashboardKind(app)
        XCTAssertTrue(waitForKind(kind, startingWith: "photo"), "\(kind.value ?? "nil")")
        XCTAssertTrue(waitForValue(element(app, "background.photoLoaded"), "yes", timeout: 15))
        attachScreenshot("background-photo")
    }

    /// Waits on `BackgroundPolicy` showing a photo while the sun is up.
    func testAutoShowsPhotoByDay() {
        let app = launch(stored: "gradient", now: Self.midday)
        choose("auto", in: app)
        XCTAssertTrue(waitForLabel(element(app, "settings.background.mode"), containing: "Auto"))
        let kind = dashboardKind(app)
        XCTAssertTrue(waitForKind(kind, startingWith: "photo"), "\(kind.value ?? "nil")")
        XCTAssertTrue(waitForValue(element(app, "background.photoLoaded"), "yes", timeout: 15))
        attachScreenshot("background-auto")
    }

    func testAutoShowsGradientAtNight() {
        let app = launch(stored: "photo", now: Self.night)
        choose("auto", in: app)
        XCTAssertTrue(waitForLabel(element(app, "settings.background.mode"), containing: "Auto"))
        let kind = dashboardKind(app)
        XCTAssertTrue(waitForValue(kind, "gradient"), "\(kind.value ?? "nil")")
        attachScreenshot("background-auto-night")
    }

    func testChoiceScreenShowsHelpForEachOption() {
        let app = launch(stored: "gradient", now: Self.midday)
        openChoiceScreen(app)
        XCTAssertTrue(waitForHelp(app, containing: "drifting sky"))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForHelp(app, containing: "blurred photo"))
        XCUIRemote.shared.press(.down)
        XCTAssertTrue(waitForHelp(app, containing: "during storms"))
    }

    func testCreditsScreenOpensWithRowsOrUnavailableNotice() {
        let app = launch(stored: "gradient", now: Self.midday)
        let row = element(app, "settings.background.credits")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<8 where !cell(app, "settings.background.credits").hasFocus {
            XCUIRemote.shared.press(.down)
            _ = waitForFocus(cell(app, "settings.background.credits"), timeout: 1)
        }
        XCTAssertTrue(cell(app, "settings.background.credits").hasFocus)
        XCUIRemote.shared.press(.select)
        let first = app.buttons["settings.credits.clear-dawn"]
        let unavailable = app.buttons["settings.credits.unavailable"]
        XCTAssertTrue(first.waitForExistence(timeout: 5) || unavailable.waitForExistence(timeout: 1))
        attachScreenshot("settings-credits")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(waitForFocus(cell(app, "settings.background.credits")))
    }

    private func launch(stored: String, now: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-settings", "1", "-resetSettings", "1", "-offline", "1", "-nightDim", "off",
            "-background", stored, "-now", now,
        ]
        app.launch()
        return app
    }

    private func openChoiceScreen(_ app: XCUIApplication) {
        let row = element(app, "settings.background.mode")
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for _ in 0..<8 where !cell(app, "settings.background.mode").hasFocus {
            XCUIRemote.shared.press(.down)
            _ = waitForFocus(cell(app, "settings.background.mode"), timeout: 1)
        }
        XCTAssertTrue(cell(app, "settings.background.mode").hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["settings.background.option.gradient"].waitForExistence(timeout: 5))
    }

    private func choose(_ mode: String, in app: XCUIApplication) {
        openChoiceScreen(app)
        let target = cell(app, "settings.background.option.\(mode)")
        for _ in 0..<3 where !target.hasFocus {
            XCUIRemote.shared.press(["gradient": .up, "photo": .down, "auto": .down][mode] ?? .down)
            _ = waitForFocus(target, timeout: 1)
        }
        XCTAssertTrue(target.hasFocus)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(waitForNonExistence(app.buttons["settings.background.option.\(mode)"]))
    }

    private func dashboardKind(_ app: XCUIApplication) -> XCUIElement {
        let row = element(app, "settings.background.mode")
        XCUIRemote.shared.press(.menu)
        if !waitForNonExistence(row, timeout: 6) {
            XCUIRemote.shared.press(.menu)
        }
        XCTAssertTrue(waitForNonExistence(row, timeout: 6))
        XCTAssertTrue(app.buttons["dashboard.card.current"].waitForExistence(timeout: 5))
        return element(app, "background.kind")
    }

    private func waitForKind(_ kind: XCUIElement, startingWith prefix: String, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "value BEGINSWITH %@", prefix)
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: kind)], timeout: timeout) == .completed
    }

    private func waitForHelp(_ app: XCUIApplication, containing text: String) -> Bool {
        waitForLabel(app.staticTexts["settings.help"], containing: text)
    }

    private func attachScreenshot(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let directory = ProcessInfo.processInfo.environment["PANE_GATE_SHOTS"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? screenshot.pngRepresentation.write(to: url)
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func cell(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.cells.containing(.any, identifier: id).firstMatch
    }
}
