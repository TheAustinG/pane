import Foundation

/// The NOAA solar position algorithm (the equations behind NOAA's solar calculator, after Meeus,
/// "Astronomical Algorithms"). Good to about a minute of time between 72° north and south.
public enum SolarPosition {
    /// Sun altitude in degrees, corrected for atmospheric refraction.
    public static func altitude(at date: Date, location: GeoPoint) -> Double {
        let sun = Ephemeris(date)
        let latitude = radians(location.latitude)
        let angle = radians(hourAngle(at: date, longitude: location.longitude, sun: sun))
        let cosZenith = sin(latitude) * sin(sun.declination) + cos(latitude) * cos(sun.declination) * cos(angle)
        let elevation = 90 - degrees(acos(min(max(cosZenith, -1), 1)))
        return elevation + refraction(elevation)
    }

    /// Local hour angle of the sun in degrees, -180 to 180: negative before local solar noon.
    public static func hourAngle(at date: Date, location: GeoPoint) -> Double {
        hourAngle(at: date, longitude: location.longitude, sun: Ephemeris(date))
    }

    /// When the sun crosses the meridian on the calendar day of `date` in `timeZone`.
    public static func solarNoon(on date: Date, location: GeoPoint, timeZone: TimeZone = .current) -> Date {
        var time = localNoon(of: date, timeZone: timeZone)
        for _ in 0..<3 {
            time -= hourAngle(at: time, location: location) * secondsPerDegree
        }
        return time
    }

    /// Sunrise on the calendar day of `date` in `timeZone`: the sun's upper limb on a sea-level
    /// horizon, with standard refraction. Nil during polar day or night.
    public static func sunrise(on date: Date, location: GeoPoint, timeZone: TimeZone = .current) -> Date? {
        horizonCrossing(on: date, location: location, timeZone: timeZone, sign: -1)
    }

    /// Sunset on the calendar day of `date` in `timeZone`. Nil during polar day or night.
    public static func sunset(on date: Date, location: GeoPoint, timeZone: TimeZone = .current) -> Date? {
        horizonCrossing(on: date, location: location, timeZone: timeZone, sign: 1)
    }

    /// 34' of refraction plus the sun's 16' semidiameter.
    static let horizonZenith = 90.833
    private static let secondsPerDegree = 240.0

    private static func horizonCrossing(on date: Date, location: GeoPoint, timeZone: TimeZone, sign: Double) -> Date? {
        var time = solarNoon(on: date, location: location, timeZone: timeZone)
        let latitude = radians(location.latitude)
        for _ in 0..<4 {
            let sun = Ephemeris(time)
            let cosine = (cos(radians(horizonZenith)) - sin(latitude) * sin(sun.declination))
                / (cos(latitude) * cos(sun.declination))
            guard abs(cosine) <= 1 else { return nil }
            let target = sign * degrees(acos(cosine))
            time -= wrapped(hourAngle(at: time, longitude: location.longitude, sun: sun) - target) * secondsPerDegree
        }
        return time
    }

    private static func localNoon(of date: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.startOfDay(for: date).addingTimeInterval(12 * 3600)
    }

    private static func hourAngle(at date: Date, longitude: Double, sun: Ephemeris) -> Double {
        let minutes = date.timeIntervalSince1970 / 60
        let trueSolarMinutes = minutes + sun.equationOfTime + 4 * longitude
        return wrapped(trueSolarMinutes / 4 - 180)
    }

    /// NOAA's piecewise refraction approximation, in degrees.
    static func refraction(_ elevation: Double) -> Double {
        let arcseconds: Double
        if elevation > 85 {
            arcseconds = 0
        } else if elevation > 5 {
            let t = tan(radians(elevation))
            arcseconds = 58.1 / t - 0.07 / (t * t * t) + 0.000086 / pow(t, 5)
        } else if elevation > -0.575 {
            let e = elevation
            arcseconds = 1735 + e * (-518.2 + e * (103.4 + e * (-12.79 + e * 0.711)))
        } else {
            arcseconds = -20.772 / tan(radians(elevation))
        }
        return arcseconds / 3600
    }

    private static func wrapped(_ degrees: Double) -> Double {
        let r = (degrees + 180).truncatingRemainder(dividingBy: 360)
        return (r < 0 ? r + 360 : r) - 180
    }
}

/// Declination and equation of time for an instant.
private struct Ephemeris {
    /// Radians.
    let declination: Double
    /// Minutes of time.
    let equationOfTime: Double

    init(_ date: Date) {
        let julianDay = date.timeIntervalSince1970 / 86400 + 2_440_587.5
        let t = (julianDay - 2_451_545) / 36525
        let meanLongitude = (280.46646 + t * (36000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let m = radians(meanAnomaly)
        let center = sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m) * (0.019993 - 0.000101 * t)
            + sin(3 * m) * 0.000289
        let omega = radians(125.04 - 1934.136 * t)
        let apparentLongitude = radians(meanLongitude + center - 0.00569 - 0.00478 * sin(omega))
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = radians(meanObliquity + 0.00256 * cos(omega))
        declination = asin(sin(obliquity) * sin(apparentLongitude))

        let y = pow(tan(obliquity / 2), 2)
        let l0 = radians(meanLongitude)
        equationOfTime = 4 * degrees(
            y * sin(2 * l0)
                - 2 * eccentricity * sin(m)
                + 4 * eccentricity * y * sin(m) * cos(2 * l0)
                - 0.5 * y * y * sin(4 * l0)
                - 1.25 * eccentricity * eccentricity * sin(2 * m)
        )
    }
}

private func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
private func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
