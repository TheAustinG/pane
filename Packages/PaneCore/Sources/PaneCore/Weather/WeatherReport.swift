import Foundation

/// The home location, chosen by city search in Settings. The Apple TV has no GPS.
public struct HomeLocation: Codable, Hashable, Sendable {
    public var name: String
    public var coordinate: GeoPoint

    public init(name: String, coordinate: GeoPoint) {
        self.name = name
        self.coordinate = coordinate
    }
}

/// One WeatherKit fetch in our own types, so tests, fixtures and the offline cache never need
/// WeatherKit values. Temperatures are Celsius; chances and humidity are 0 to 1.
public struct WeatherReport: Codable, Hashable, Sendable {
    public var fetchedAt: Date
    public var location: GeoPoint
    public var current: CurrentConditions
    /// In date order. WeatherKit includes about a day of past hours, which `-now` replays use.
    public var hourly: [HourForecast]
    /// In date order, starting with today.
    public var daily: [DayForecast]
    /// Next-hour precipitation by minute; nil where WeatherKit does not cover the location.
    public var minutes: [MinuteForecast]?
    /// Active alerts; nil where WeatherKit does not cover the location.
    public var alerts: [WeatherAlertInfo]?

    public init(
        fetchedAt: Date,
        location: GeoPoint,
        current: CurrentConditions,
        hourly: [HourForecast],
        daily: [DayForecast],
        minutes: [MinuteForecast]?,
        alerts: [WeatherAlertInfo]?
    ) {
        self.fetchedAt = fetchedAt
        self.location = location
        self.current = current
        self.hourly = hourly
        self.daily = daily
        self.minutes = minutes
        self.alerts = alerts
    }
}

public struct CurrentConditions: Codable, Hashable, Sendable {
    public var date: Date
    public var temperature: Double
    public var apparentTemperature: Double
    public var humidity: Double
    /// `WeatherKit.WeatherCondition.rawValue`, for example `mostlyCloudy`.
    public var condition: String
    public var symbolName: String
    public var isDaylight: Bool

    public init(
        date: Date,
        temperature: Double,
        apparentTemperature: Double,
        humidity: Double,
        condition: String,
        symbolName: String,
        isDaylight: Bool
    ) {
        self.date = date
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.humidity = humidity
        self.condition = condition
        self.symbolName = symbolName
        self.isDaylight = isDaylight
    }
}

public struct HourForecast: Codable, Hashable, Sendable {
    /// Start of the hour.
    public var date: Date
    public var temperature: Double
    public var condition: String
    public var symbolName: String
    public var precipitationChance: Double
    public var isDaylight: Bool

    public init(
        date: Date,
        temperature: Double,
        condition: String,
        symbolName: String,
        precipitationChance: Double,
        isDaylight: Bool
    ) {
        self.date = date
        self.temperature = temperature
        self.condition = condition
        self.symbolName = symbolName
        self.precipitationChance = precipitationChance
        self.isDaylight = isDaylight
    }
}

public struct DayForecast: Codable, Hashable, Sendable {
    /// Start of the day in the location's time zone.
    public var date: Date
    public var high: Double
    public var low: Double
    public var condition: String
    public var symbolName: String
    public var precipitationChance: Double
    public var sunrise: Date?
    public var sunset: Date?

    public init(
        date: Date,
        high: Double,
        low: Double,
        condition: String,
        symbolName: String,
        precipitationChance: Double,
        sunrise: Date?,
        sunset: Date?
    ) {
        self.date = date
        self.high = high
        self.low = low
        self.condition = condition
        self.symbolName = symbolName
        self.precipitationChance = precipitationChance
        self.sunrise = sunrise
        self.sunset = sunset
    }
}

public struct MinuteForecast: Codable, Hashable, Sendable {
    public var date: Date
    public var precipitationChance: Double
    /// Millimeters per hour.
    public var precipitationIntensity: Double

    public init(date: Date, precipitationChance: Double, precipitationIntensity: Double) {
        self.date = date
        self.precipitationChance = precipitationChance
        self.precipitationIntensity = precipitationIntensity
    }
}

/// An alert as issued. Apple's rules: never alter `summary`, name the issuing agency (`source`),
/// and link to `detailsURL` (a QR code on the TV).
public struct WeatherAlertInfo: Codable, Hashable, Sendable {
    public var id: String
    public var summary: String
    public var source: String
    /// `WeatherKit.WeatherSeverity.rawValue`.
    public var severity: String
    public var detailsURL: URL
    public var region: String?

    public init(id: String, summary: String, source: String, severity: String, detailsURL: URL, region: String?) {
        self.id = id
        self.summary = summary
        self.source = source
        self.severity = severity
        self.detailsURL = detailsURL
        self.region = region
    }
}

/// What Apple requires on screen next to WeatherKit data: the Apple Weather mark and the legal page.
public struct WeatherAttributionInfo: Codable, Hashable, Sendable {
    public var serviceName: String
    public var legalPageURL: URL
    /// The combined mark drawn for dark backgrounds, which every Pane surface is.
    public var combinedMarkDarkURL: URL
    public var combinedMarkLightURL: URL

    public init(serviceName: String, legalPageURL: URL, combinedMarkDarkURL: URL, combinedMarkLightURL: URL) {
        self.serviceName = serviceName
        self.legalPageURL = legalPageURL
        self.combinedMarkDarkURL = combinedMarkDarkURL
        self.combinedMarkLightURL = combinedMarkLightURL
    }

    public static let fallbackLegalPageURL = URL(string: "https://weatherkit.apple.com/legal-attribution.html")!
}
