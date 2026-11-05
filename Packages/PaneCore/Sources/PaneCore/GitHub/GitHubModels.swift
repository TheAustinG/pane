import Foundation

/// A day on the contribution calendar, as GitHub names it (`yyyy-MM-dd`), with no time or zone.
public struct CalendarDay: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `yyyy-MM-dd`.
    public init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    /// The day `date` falls on in `calendar`'s time zone.
    public init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDay, rhs: CalendarDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public struct ContributionDay: Hashable, Sendable, Codable {
    public let day: CalendarDay
    public let count: Int
    /// GitHub's quartile, 0 (none) to 4 (most).
    public let level: Int

    public init(day: CalendarDay, count: Int, level: Int) {
        self.day = day
        self.count = count
        self.level = level
    }
}

/// The contribution calendar as GitHub returned it, oldest day first.
public struct ContributionCalendar: Hashable, Sendable, Codable {
    public let days: [ContributionDay]

    public init(days: [ContributionDay]) {
        self.days = days
    }
}

/// The newest commit pushed to any of the viewer's repositories.
public struct LatestCommit: Hashable, Sendable, Codable {
    /// `owner/name`.
    public let repository: String
    /// The branch it was pushed to, without `refs/heads/`.
    public let branch: String?
    public let sha: String
    /// The first line of the commit message.
    public let headline: String
    /// When it was pushed.
    public let date: Date

    public init(repository: String, branch: String?, sha: String, headline: String, date: Date) {
        self.repository = repository
        self.branch = branch
        self.sha = sha
        self.headline = headline
        self.date = date
    }

    /// The repository name without its owner, as the card shows it.
    public var repositoryName: String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }
}

/// Everything the GitHub card shows, from one refresh.
public struct GitHubSnapshot: Hashable, Sendable, Codable {
    public let login: String
    public let calendar: ContributionCalendar
    public let latestCommit: LatestCommit?
    public let fetchedAt: Date

    public init(login: String, calendar: ContributionCalendar, latestCommit: LatestCommit?, fetchedAt: Date) {
        self.login = login
        self.calendar = calendar
        self.latestCommit = latestCommit
        self.fetchedAt = fetchedAt
    }
}

/// What the card draws for the contribution pane, worked out for the app's "today".
public struct ContributionSummary: Hashable, Sendable {
    /// Consecutive days with a contribution, ending today, or yesterday when today has none yet.
    public let streak: Int
    public let todayCount: Int
    /// `weeks * 7` levels, week columns oldest first, Sunday at the top; -1 for days after today.
    public let levels: [Int]

    public init(streak: Int, todayCount: Int, levels: [Int]) {
        self.streak = streak
        self.todayCount = todayCount
        self.levels = levels
    }
}

/// The state of one of the Code card's connections (GitHub or Portainer).
public enum CodeConnection: Hashable, Sendable {
    /// No token (and for Portainer, no address) yet.
    case notConfigured
    case loading
    case ready
    /// The token was refused. No retries until it changes.
    case authFailed
    /// The last refresh failed; `retryAt` is when the next one starts.
    case failed(since: Date, retryAt: Date?)

    public var isReady: Bool { self == .ready }
}

/// Why a setup screen's connection test failed. Never carries a token.
public enum CodeSetupError: Error, Hashable, Sendable {
    case badAddress
    case unreachable
    case invalidToken
    case timeout
    /// The token works but lacks a permission, named here (such as "Actions").
    case missingPermission(String)
    /// Portainer has no environment with this id.
    case unknownEnvironment
    /// The server presented a certificate other than the pinned one.
    case certificateChanged
    case unexpectedReply(String)
}
