import Foundation

extension WeatherAlertInfo {
    /// `endDate` from a `WeatherKit.WeatherAlert` encoded by a default `JSONEncoder`. The key is
    /// undocumented, only part of the alert's Codable form, so nil (no known end) is the fallback
    /// when it is missing or renamed, never an error.
    static func endDate(fromEncodedAlert data: Data) -> Date? {
        struct Encoded: Decodable {
            let endDate: Date?
        }
        return (try? JSONDecoder().decode(Encoded.self, from: data))?.endDate
    }
}
