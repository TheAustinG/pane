import Foundation
import Testing
@testable import PaneCore

private func entry(_ slot: String, licenseURL: String? = "\"https://creativecommons.org/licenses/by/4.0/\"") -> String {
    """
    {
      "slot": "\(slot)",
      "title": "Sample \(slot)",
      "creator": "Sample Creator",
      "license": "CC BY 4.0",
      \(licenseURL.map { "\"licenseURL\": \($0)," } ?? "")
      "sourcePage": "https://example.invalid/photos/\(slot)",
      "attribution": "Sample \(slot) by Sample Creator, CC BY 4.0"
    }
    """
}

private func json(_ entries: [String]) -> Data {
    Data("{\"photos\": [\(entries.joined(separator: ","))]}".utf8)
}

@Suite("Photo credits")
struct PhotoCreditsTests {
    @Test func decodesEveryField() throws {
        let credits = try PhotoCredits.decode(json([entry("clear-dawn"), entry("partlyCloudy-night", licenseURL: nil)]))
        #expect(credits.photos.count == 2)
        let dawn = try #require(credits.credit(for: PhotoKey(condition: .clear, time: .dawn)))
        #expect(dawn.slot == "clear-dawn")
        #expect(dawn.key == PhotoKey(condition: .clear, time: .dawn))
        #expect(dawn.title == "Sample clear-dawn")
        #expect(dawn.creator == "Sample Creator")
        #expect(dawn.license == "CC BY 4.0")
        #expect(dawn.licenseURL == URL(string: "https://creativecommons.org/licenses/by/4.0/"))
        #expect(dawn.sourcePage == URL(string: "https://example.invalid/photos/clear-dawn"))
        #expect(dawn.attribution == "Sample clear-dawn by Sample Creator, CC BY 4.0")
        #expect(credits.credit(for: PhotoKey(condition: .partlyCloudy, time: .night))?.licenseURL == nil)
        #expect(credits.credit(for: PhotoKey(condition: .fog, time: .day)) == nil)
    }

    @Test func aNullLicenseURLDecodes() throws {
        let credits = try PhotoCredits.decode(json([entry("snow-day", licenseURL: "null")]))
        #expect(credits.photos.first?.licenseURL == nil)
    }

    @Test func missingSlotsListsTheRestInOrder() throws {
        let credits = try PhotoCredits.decode(json([entry("clear-day"), entry("fog-night")]))
        let missing = credits.missingSlots()
        #expect(missing.count == 26)
        #expect(missing.first?.name == "clear-dawn")
        #expect(!missing.map(\.name).contains("clear-day"))
        #expect(!missing.map(\.name).contains("fog-night"))
        #expect(missing == PhotoKey.all.filter { $0.name != "clear-day" && $0.name != "fog-night" })
    }

    @Test func aFullSetHasNoMissingSlots() throws {
        let credits = try PhotoCredits.decode(json(PhotoKey.all.map { entry($0.name) }))
        #expect(credits.missingSlots().isEmpty)
    }

    @Test func aDuplicateSlotIsRejected() {
        #expect(throws: PhotoCredits.ValidationError.duplicateSlot("rain-dusk")) {
            try PhotoCredits.decode(json([entry("rain-dusk"), entry("rain-day"), entry("rain-dusk")]))
        }
    }

    @Test(arguments: ["clear-noon", "sunny-day", "clear", "partly-cloudy-day"])
    func anUnknownSlotIsRejected(_ slot: String) {
        #expect(throws: PhotoCredits.ValidationError.unknownSlot(slot)) {
            try PhotoCredits.decode(json([entry("clear-dawn"), entry(slot)]))
        }
    }

    @Test func aMissingFieldIsADecodingError() {
        let data = Data(#"{"photos": [{"slot": "clear-dawn", "title": "Sample"}]}"#.utf8)
        #expect(throws: DecodingError.self) {
            try PhotoCredits.decode(data)
        }
    }
}
