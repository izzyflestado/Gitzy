import Foundation

/// The GraphQL queries Gitzy sends. Nothing else is ever requested.
nonisolated enum GitHubQueries {
    static let viewerLogin = "query { viewer { login } }"

    private static let calendarFields =
        "contributionCalendar { totalContributions weeks { contributionDays { date contributionCount contributionLevel weekday } } }"

    /// GitHub's own graph: the last year, ending now.
    static let lastYear = "query { viewer { login contributionsCollection { \(calendarFields) } } }"

    /// One whole calendar year per alias (`y2025`), all in a single request.
    /// Each window is just under one year long, which is the most GitHub allows per collection.
    static func calendarYears(_ years: [Int]) -> (query: String, variables: [String: String]) {
        var declarations: [String] = []
        var selections: [String] = []
        var variables: [String: String] = [:]
        for year in years {
            declarations.append("$from\(year): DateTime!, $to\(year): DateTime!")
            selections.append("y\(year): contributionsCollection(from: $from\(year), to: $to\(year)) { \(calendarFields) }")
            variables["from\(year)"] = String(format: "%04d-01-01T00:00:00Z", year)
            variables["to\(year)"] = String(format: "%04d-12-31T23:59:59Z", year)
        }
        let query = "query(\(declarations.joined(separator: ", "))) { viewer { login \(selections.joined(separator: " ")) } }"
        return (query, variables)
    }
}

nonisolated struct ParsedCalendar: Equatable, Sendable {
    let total: Int
    let weeks: [[ContributionDay]]
}

nonisolated struct ParsedResponse: Equatable, Sendable {
    let login: String
    /// Keyed by the name GitHub used: "contributionsCollection" or an alias like "y2025".
    let calendars: [String: ParsedCalendar]
}

/// Turns GitHub's JSON into plain values, or throws a GitHubError.
nonisolated enum GitHubParser {
    static func parse(_ data: Data, rateLimitExhausted: Bool = false, retryAfter: Date? = nil) throws -> ParsedResponse {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw GitHubError.unexpectedResponse
        }

        if let errors = envelope.errors, !errors.isEmpty {
            throw GitHubError.from(
                graphQLErrors: errors.map { ($0.type, $0.message) },
                rateLimitExhausted: rateLimitExhausted,
                retryAfter: retryAfter
            )
        }
        guard let viewer = envelope.data?.viewer else { throw GitHubError.unexpectedResponse }

        var calendars: [String: ParsedCalendar] = [:]
        for (name, collection) in viewer.collections {
            let calendar = collection.contributionCalendar
            let weeks = calendar.weeks.map { week in
                week.contributionDays.map { day in
                    ContributionDay(
                        date: day.date,
                        count: day.contributionCount,
                        level: ContributionLevel(githubName: day.contributionLevel),
                        weekday: day.weekday
                    )
                }
            }
            calendars[name] = ParsedCalendar(total: calendar.totalContributions, weeks: weeks)
        }
        return ParsedResponse(login: viewer.login, calendars: calendars)
    }
}

// MARK: JSON shapes

private nonisolated struct Envelope: Decodable {
    let data: DataPayload?
    let errors: [ErrorPayload]?
}

private nonisolated struct DataPayload: Decodable {
    let viewer: ViewerPayload?
}

private nonisolated struct ErrorPayload: Decodable {
    let type: String?
    let message: String
}

/// `viewer` holds `login` plus one calendar per alias, and the alias names are not fixed.
private nonisolated struct ViewerPayload: Decodable {
    let login: String
    let collections: [String: CollectionPayload]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        login = try container.decode(String.self, forKey: AnyKey("login"))
        var found: [String: CollectionPayload] = [:]
        for key in container.allKeys where key.stringValue != "login" {
            found[key.stringValue] = try container.decode(CollectionPayload.self, forKey: key)
        }
        collections = found
    }
}

private nonisolated struct CollectionPayload: Decodable {
    let contributionCalendar: CalendarPayload
}

private nonisolated struct CalendarPayload: Decodable {
    let totalContributions: Int
    let weeks: [WeekPayload]
}

private nonisolated struct WeekPayload: Decodable {
    let contributionDays: [DayPayload]
}

private nonisolated struct DayPayload: Decodable {
    let date: String
    let contributionCount: Int
    let contributionLevel: String
    let weekday: Int
}

private nonisolated struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
