import Foundation
import Testing
@testable import Gitzy

/// GitHub replies written out by hand. None of them contains a token or any other secret.
nonisolated struct GitHubParserTests {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    private let lastYearReply = """
    {"data":{"viewer":{"login":"octocat","contributionsCollection":{"contributionCalendar":{
      "totalContributions":7,
      "weeks":[
        {"contributionDays":[
          {"date":"2026-10-24","contributionCount":0,"contributionLevel":"NONE","weekday":6}
        ]},
        {"contributionDays":[
          {"date":"2026-10-25","contributionCount":3,"contributionLevel":"SECOND_QUARTILE","weekday":0},
          {"date":"2026-10-26","contributionCount":4,"contributionLevel":"FOURTH_QUARTILE","weekday":1}
        ]}
      ]}}}}}
    """

    // MARK: Successful replies

    @Test func parsesTheLastYearReply() throws {
        let parsed = try GitHubParser.parse(data(lastYearReply))
        #expect(parsed.login == "octocat")
        #expect(Set(parsed.calendars.keys) == ["contributionsCollection"])

        let calendar = try #require(parsed.calendars["contributionsCollection"])
        #expect(calendar.total == 7)
        #expect(calendar.weeks.count == 2)
        #expect(calendar.weeks[0] == [ContributionDay(date: "2026-10-24", count: 0, level: .none, weekday: 6)])
        #expect(calendar.weeks[1].map(\.count) == [3, 4])
        #expect(calendar.weeks[1].map(\.level) == [.second, .fourth])
        #expect(calendar.weeks[1].map(\.weekday) == [0, 1])
    }

    @Test func parsesAliasedYears() throws {
        let year = """
        {"contributionCalendar":{"totalContributions":1,"weeks":[{"contributionDays":[
          {"date":"2025-06-02","contributionCount":1,"contributionLevel":"FIRST_QUARTILE","weekday":1}]}]}}
        """
        let reply = "{\"data\":{\"viewer\":{\"login\":\"octocat\",\"y2025\":\(year),\"y2024\":\(year)}}}"
        let parsed = try GitHubParser.parse(data(reply))
        #expect(Set(parsed.calendars.keys) == ["y2025", "y2024"])
        #expect(parsed.calendars["y2025"]?.weeks.first?.first?.level == .first)
    }

    @Test func parsesALoginOnlyReply() throws {
        let parsed = try GitHubParser.parse(data(#"{"data":{"viewer":{"login":"octocat"}}}"#))
        #expect(parsed.login == "octocat")
        #expect(parsed.calendars.isEmpty)
    }

    @Test func unknownLevelNamesCountAsNone() {
        #expect(ContributionLevel(githubName: "NONE") == .none)
        #expect(ContributionLevel(githubName: "FIRST_QUARTILE") == .first)
        #expect(ContributionLevel(githubName: "SECOND_QUARTILE") == .second)
        #expect(ContributionLevel(githubName: "THIRD_QUARTILE") == .third)
        #expect(ContributionLevel(githubName: "FOURTH_QUARTILE") == .fourth)
        #expect(ContributionLevel(githubName: "SOMETHING_NEW") == .none)
    }

    // MARK: Errors inside a reply

    @Test func rateLimitedError() {
        let reply = #"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded for user ID 1."}]}"#
        #expect(throws: GitHubError.rateLimited(retryAfter: nil)) { try GitHubParser.parse(data(reply)) }
    }

    @Test func exhaustedQuotaCountsAsRateLimitWhateverTheErrorSays() {
        let reply = #"{"errors":[{"type":"SOMETHING","message":"Something went wrong"}]}"#
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(throws: GitHubError.rateLimited(retryAfter: reset)) {
            try GitHubParser.parse(data(reply), rateLimitExhausted: true, retryAfter: reset)
        }
    }

    @Test func insufficientScopesError() {
        let reply = #"{"errors":[{"type":"INSUFFICIENT_SCOPES","message":"Your token has not been granted the required scopes."}]}"#
        #expect(throws: GitHubError.insufficientScope) { try GitHubParser.parse(data(reply)) }
    }

    @Test func otherErrorsKeepGitHubsText() {
        let reply = #"{"errors":[{"type":"NOT_FOUND","message":"Could not resolve to a User."}]}"#
        #expect(throws: GitHubError.graphQL("Could not resolve to a User.")) { try GitHubParser.parse(data(reply)) }
    }

    // MARK: Replies that make no sense

    @Test func malformedReplies() {
        for text in ["not json", "", "[]", "{}", #"{"data":null}"#, #"{"data":{"viewer":null}}"#, #"{"data":{"viewer":{}}}"#] {
            #expect(throws: GitHubError.unexpectedResponse, "\(text)") { try GitHubParser.parse(data(text)) }
        }
    }

    @Test func aCalendarMissingFieldsIsRejected() {
        let reply = #"{"data":{"viewer":{"login":"octocat","contributionsCollection":{"contributionCalendar":{"totalContributions":1}}}}}"#
        #expect(throws: GitHubError.unexpectedResponse) { try GitHubParser.parse(data(reply)) }
    }

    // MARK: Queries

    @Test func simpleQueries() {
        #expect(GitHubQueries.viewerLogin == "query { viewer { login } }")
        #expect(GitHubQueries.lastYear.contains("contributionsCollection { contributionCalendar"))
        #expect(!GitHubQueries.lastYear.contains("from:"))
        #expect(GitHubQueries.lastYear.contains("weekday"))
    }

    @Test func yearQueryHasOneAliasPerYear() {
        let request = GitHubQueries.calendarYears([2025, 2024])
        #expect(request.query.hasPrefix("query($from2025: DateTime!, $to2025: DateTime!, $from2024: DateTime!, $to2024: DateTime!)"))
        #expect(request.query.contains("y2025: contributionsCollection(from: $from2025, to: $to2025)"))
        #expect(request.query.contains("y2024: contributionsCollection(from: $from2024, to: $to2024)"))
        #expect(request.variables == [
            "from2025": "2025-01-01T00:00:00Z", "to2025": "2025-12-31T23:59:59Z",
            "from2024": "2024-01-01T00:00:00Z", "to2024": "2024-12-31T23:59:59Z",
        ])
    }

    @Test func yearQueryBracesAreBalanced() {
        let query = GitHubQueries.calendarYears([2023, 2022, 2021, 2020]).query
        #expect(query.filter { $0 == "{" }.count == query.filter { $0 == "}" }.count)
        #expect(query.filter { $0 == "(" }.count == query.filter { $0 == ")" }.count)
    }

    @Test func earlyYearsArePaddedToFourDigits() {
        let request = GitHubQueries.calendarYears([2008])
        #expect(request.variables["from2008"] == "2008-01-01T00:00:00Z")
    }
}
