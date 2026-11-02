import Foundation
import Testing
@testable import PaneCore

func utc(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

private let chicago = GeoPoint(latitude: 41.88, longitude: -87.63)
private let greenwich = GeoPoint(latitude: 51.48, longitude: 0.0)
private let chicagoZone = TimeZone(identifier: "America/Chicago")!
private let londonZone = TimeZone(identifier: "Europe/London")!

struct AltitudeReference: Sendable, CustomTestStringConvertible {
    let place: GeoPoint
    let time: String
    let altitude: Double

    var testDescription: String { "\(place.latitude), \(place.longitude) at \(time)" }
}

// Reference altitudes from the US Naval Observatory, "Altitude and Azimuth of the Sun or Moon
// During One Day" (aa.usno.navy.mil/data/AltAz, body Sun, UT, 1-minute steps), published to
// 0.1°. USNO adds refraction only above the horizon, which changes the -7° case by about 0.05°.
private let altitudeReferences = [
    AltitudeReference(place: chicago, time: "2026-06-21T17:52:00Z", altitude: 71.6),
    AltitudeReference(place: chicago, time: "2026-06-21T22:30:00Z", altitude: 30.4),
    AltitudeReference(place: chicago, time: "2026-12-21T17:49:00Z", altitude: 24.7),
    AltitudeReference(place: chicago, time: "2026-12-21T23:00:00Z", altitude: -7.0),
    AltitudeReference(place: chicago, time: "2026-11-01T15:00:00Z", altitude: 23.4),
    AltitudeReference(place: greenwich, time: "2026-06-21T12:02:00Z", altitude: 62.0),
    AltitudeReference(place: greenwich, time: "2026-06-21T15:00:00Z", altitude: 45.9),
    AltitudeReference(place: greenwich, time: "2026-12-21T12:00:00Z", altitude: 15.1),
    AltitudeReference(place: greenwich, time: "2026-03-20T09:00:00Z", altitude: 25.2),
]

@Test(arguments: altitudeReferences)
func altitudeMatchesPublishedValues(reference: AltitudeReference) {
    let altitude = SolarPosition.altitude(at: utc(reference.time), location: reference.place)
    #expect(abs(altitude - reference.altitude) < 0.15, "computed \(altitude)°")
}

struct DaylightReference: Sendable, CustomTestStringConvertible {
    let place: GeoPoint
    let zone: TimeZone
    let day: String
    let sunrise: String
    let sunset: String

    var testDescription: String { "\(place.latitude), \(place.longitude) on \(day)" }
}

// Reference times from the US Naval Observatory, "Sun and Moon Data for One Day"
// (aa.usno.navy.mil/api/rstt/oneday), published to the minute, converted to UTC.
private let daylightReferences = [
    // 05:16 and 20:29 CDT
    DaylightReference(place: chicago, zone: chicagoZone, day: "2026-06-21T17:00:00Z", sunrise: "2026-06-21T10:16:00Z", sunset: "2026-06-22T01:29:00Z"),
    // 07:15 and 16:23 CST
    DaylightReference(place: chicago, zone: chicagoZone, day: "2026-12-21T18:00:00Z", sunrise: "2026-12-21T13:15:00Z", sunset: "2026-12-21T22:23:00Z"),
    // 06:23 and 16:45 CST, the first day after the DST change
    DaylightReference(place: chicago, zone: chicagoZone, day: "2026-11-01T18:00:00Z", sunrise: "2026-11-01T12:23:00Z", sunset: "2026-11-01T22:45:00Z"),
    // 04:43 and 21:21 BST
    DaylightReference(place: greenwich, zone: londonZone, day: "2026-06-21T12:00:00Z", sunrise: "2026-06-21T03:43:00Z", sunset: "2026-06-21T20:21:00Z"),
    // 08:03 and 15:53 GMT
    DaylightReference(place: greenwich, zone: londonZone, day: "2026-12-21T12:00:00Z", sunrise: "2026-12-21T08:03:00Z", sunset: "2026-12-21T15:53:00Z"),
]

@Test(arguments: daylightReferences)
func sunriseAndSunsetMatchPublishedTimes(reference: DaylightReference) throws {
    let day = utc(reference.day)
    let sunrise = try #require(SolarPosition.sunrise(on: day, location: reference.place, timeZone: reference.zone))
    let sunset = try #require(SolarPosition.sunset(on: day, location: reference.place, timeZone: reference.zone))
    #expect(abs(sunrise.timeIntervalSince(utc(reference.sunrise))) < 120, "sunrise \(sunrise)")
    #expect(abs(sunset.timeIntervalSince(utc(reference.sunset))) < 120, "sunset \(sunset)")
}

@Test func sunriseIsFoundFromAnyTimeOfTheLocalDay() throws {
    let early = try #require(SolarPosition.sunrise(on: utc("2026-11-01T05:30:00Z"), location: chicago, timeZone: chicagoZone))
    let late = try #require(SolarPosition.sunrise(on: utc("2026-11-02T05:30:00Z"), location: chicago, timeZone: chicagoZone))
    #expect(abs(early.timeIntervalSince(late)) < 1, "11:30 PM CST is still November 1")
}

@Test func solarNoonMatchesPublishedTransit() {
    // USNO upper transit: 12:52 CDT in Chicago on 2026-06-21, 11:58 GMT at Greenwich on 2026-12-21.
    let chicagoNoon = SolarPosition.solarNoon(on: utc("2026-06-21T17:00:00Z"), location: chicago, timeZone: chicagoZone)
    let greenwichNoon = SolarPosition.solarNoon(on: utc("2026-12-21T12:00:00Z"), location: greenwich, timeZone: londonZone)
    #expect(abs(chicagoNoon.timeIntervalSince(utc("2026-06-21T17:52:00Z"))) < 120)
    #expect(abs(greenwichNoon.timeIntervalSince(utc("2026-12-21T11:58:00Z"))) < 120)
    #expect(abs(SolarPosition.hourAngle(at: chicagoNoon, location: chicago)) < 0.01)
}

@Test func altitudeAtSunriseSitsOnTheRefractedHorizon() throws {
    let sunrise = try #require(SolarPosition.sunrise(on: utc("2026-11-01T18:00:00Z"), location: chicago, timeZone: chicagoZone))
    let altitude = SolarPosition.altitude(at: sunrise, location: chicago)
    // Center 0.833° below the geometric horizon, lifted about 0.55° by refraction.
    #expect(altitude > -0.5 && altitude < 0)
}

@Test func hourAngleIsNegativeBeforeNoon() {
    #expect(SolarPosition.hourAngle(at: utc("2026-11-01T15:00:00Z"), location: chicago) < 0)
    #expect(SolarPosition.hourAngle(at: utc("2026-11-01T20:00:00Z"), location: chicago) > 0)
}

@Test func polarDayAndNightHaveNoSunriseOrSunset() {
    let svalbard = GeoPoint(latitude: 78.22, longitude: 15.65)
    let zone = TimeZone(identifier: "Arctic/Longyearbyen")!
    #expect(SolarPosition.sunrise(on: utc("2026-06-21T12:00:00Z"), location: svalbard, timeZone: zone) == nil)
    #expect(SolarPosition.sunset(on: utc("2026-12-21T12:00:00Z"), location: svalbard, timeZone: zone) == nil)
    #expect(SolarPosition.altitude(at: utc("2026-06-21T23:00:00Z"), location: svalbard) > 0)
    #expect(SolarPosition.altitude(at: utc("2026-12-21T11:00:00Z"), location: svalbard) < -6)
}

@Test func refractionIsContinuousAcrossItsBranches() {
    for edge in [-0.575, 5.0] {
        #expect(abs(SolarPosition.refraction(edge - 1e-6) - SolarPosition.refraction(edge + 1e-6)) < 0.001)
    }
    #expect(SolarPosition.refraction(90) == 0)
}
