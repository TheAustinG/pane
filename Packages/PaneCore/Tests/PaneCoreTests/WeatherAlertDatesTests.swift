import Foundation
import Testing
@testable import PaneCore

/// Shaped like a `WeatherKit.WeatherAlert` encoded by a default `JSONEncoder`; the values are made up.
private func encodedAlert(endKey: String = "endDate", endValue: String = "815610600") -> Data {
    Data("""
    {"importance":"high","date":815400000,"issuedDate":815400000,"summary":"Flood Warning",\
    "severity":"severe","description":"Flood Warning","\(endKey)":\(endValue),\
    "id":"00000000-0000-0000-0000-000000000000","expirationDate":815418000,"onsetTime":815400000,\
    "detailsURL":"https://example.com/alerts","source":"National Weather Service","metadata":{}}
    """.utf8)
}

@Suite("Weather alert dates")
struct WeatherAlertDatesTests {
    @Test func endDateIsSecondsSince2001() {
        let end = WeatherAlertInfo.endDate(fromEncodedAlert: encodedAlert())
        #expect(end == Date(timeIntervalSinceReferenceDate: 815_610_600))
        #expect(end?.formatted(.iso8601) == "2026-11-05T22:30:00Z")
    }

    @Test func anythingElseIsNoKnownEnd() {
        #expect(WeatherAlertInfo.endDate(fromEncodedAlert: encodedAlert(endKey: "eventEndDate")) == nil)
        #expect(WeatherAlertInfo.endDate(fromEncodedAlert: encodedAlert(endValue: "null")) == nil)
        #expect(WeatherAlertInfo.endDate(fromEncodedAlert: encodedAlert(endValue: #""tomorrow""#)) == nil)
        #expect(WeatherAlertInfo.endDate(fromEncodedAlert: Data("not json".utf8)) == nil)
        #expect(WeatherAlertInfo.endDate(fromEncodedAlert: Data()) == nil)
    }

    @Test func cachedAlertsWithoutAnEndStillDecode() throws {
        let cached = Data("""
        {"id":"Flood Warning|National Weather Service|","summary":"Flood Warning","source":"National Weather Service",\
        "severity":"severe","detailsURL":"https://example.com/alerts"}
        """.utf8)
        let alert = try JSONDecoder().decode(WeatherAlertInfo.self, from: cached)
        #expect(alert.endDate == nil)
        #expect(alert.region == nil)
        #expect(!alert.hasEnded(at: .distantFuture))
    }

    @Test func endDateRoundTripsAndEndsAtItsTime() throws {
        let end = Date(timeIntervalSinceReferenceDate: 815_610_600)
        let alert = StormFixture.alert("a", endDate: end)
        let decoded = try JSONDecoder().decode(WeatherAlertInfo.self, from: JSONEncoder().encode(alert))
        #expect(decoded == alert)
        #expect(!alert.hasEnded(at: end.addingTimeInterval(-1)))
        #expect(alert.hasEnded(at: end))
    }
}
