import XCTest

@MainActor
extension XCTestCase {
    func waitForFocus(_ element: XCUIElement, is focused: Bool = true, timeout: TimeInterval = 5) -> Bool {
        wait(for: element, NSPredicate(format: "hasFocus == %@", NSNumber(value: focused)), timeout: timeout)
    }

    func waitForValue(_ element: XCUIElement, _ value: String, timeout: TimeInterval = 5) -> Bool {
        wait(for: element, NSPredicate(format: "value == %@", value), timeout: timeout)
    }

    func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 5) -> Bool {
        wait(for: element, NSPredicate(format: "label CONTAINS %@", text), timeout: timeout)
    }

    func waitForNonExistence(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        wait(for: element, NSPredicate(format: "exists == false"), timeout: timeout)
    }

    private func wait(for element: XCUIElement, _ predicate: NSPredicate, timeout: TimeInterval) -> Bool {
        XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: timeout) == .completed
    }
}
