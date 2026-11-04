import Foundation
import Synchronization

/// One HTTP exchange. The GitHub and Portainer clients take it so tests and fixture runs can
/// answer from recorded responses.
public protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Counts requests across tasks, for the soak log.
final class RequestCounter: Sendable {
    private let value = Mutex(0)

    var count: Int { value.withLock { $0 } }

    func increment() {
        value.withLock { $0 += 1 }
    }
}

struct CountingHTTPClient: HTTPClient {
    let base: any HTTPClient
    let counter: RequestCounter

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        counter.increment()
        return try await base.data(for: request)
    }
}

/// Timestamps as GitHub and Docker write them: ISO 8601 with or without fractional seconds (Docker
/// writes nanoseconds), `Z` or an offset, and sometimes a space instead of the `T`.
enum CodeDate {
    static func parse(_ text: String) -> Date? {
        var value = text.trimmingCharacters(in: .whitespaces)
        if let separator = value.index(value.startIndex, offsetBy: 10, limitedBy: value.endIndex),
           separator < value.endIndex, value[separator] == " " {
            value.replaceSubrange(separator...separator, with: "T")
        }
        return try? Date.ISO8601FormatStyle().parse(value)
    }

    static func string(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle())
    }

    static let decodingStrategy = JSONDecoder.DateDecodingStrategy.custom { decoder in
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = parse(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unreadable date")
        }
        return date
    }
}
