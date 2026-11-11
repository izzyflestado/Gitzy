import Foundation
import Testing
@testable import Gitzy

/// "Recent activity": the request, reading GitHub's reply, and putting pages together.
/// The replies are written out by hand. None of them contains a token or any other secret.
nonisolated struct ActivityTests {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    private func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func item(_ id: String, _ iso: String) -> ActivityItem {
        ActivityItem(id: id, kind: .commits, action: "Made 1 commit", repo: "a/b", detail: nil, date: date(iso), url: nil)
    }

    private let reply = """
    {"data":{"viewer":{"contributionsCollection":{
      "commitContributionsByRepository":[
        {"repository":{"nameWithOwner":"octocat/hello","url":"https://github.com/octocat/hello"},
         "contributions":{"nodes":[
           {"commitCount":3,"occurredAt":"2026-11-09T00:00:00Z"},
           {"commitCount":1,"occurredAt":"2026-11-02T00:00:00Z"}]}}],
      "pullRequestContributions":{"nodes":[
        {"occurredAt":"2026-11-08T10:30:00Z","pullRequest":{"title":"Fix the crash","number":12,
          "url":"https://github.com/octocat/hello/pull/12","repository":{"nameWithOwner":"octocat/hello"}}}]},
      "issueContributions":{"nodes":[
        {"occurredAt":"2026-11-07T09:00:00Z","issue":{"title":"Window flickers","number":5,
          "url":"https://github.com/octocat/hello/issues/5","repository":{"nameWithOwner":"octocat/hello"}}}]},
      "pullRequestReviewContributions":{"nodes":[
        {"occurredAt":"2026-11-06T09:00:00Z","pullRequest":{"title":"Add dark mode","number":9,
          "url":"https://github.com/friend/app/pull/9","repository":{"nameWithOwner":"friend/app"}}}]},
      "repositoryContributions":{"nodes":[
        {"occurredAt":"2026-11-01T08:00:00Z","repository":{"nameWithOwner":"octocat/new-thing","url":"https://github.com/octocat/new-thing"}}]}
    }}}}
    """

    // MARK: Reading the reply

    @Test func readsAllFiveKindsNewestFirst() throws {
        let items = try ActivityParser.parse(data(reply))
        #expect(items.map(\.action) == [
            "Made 3 commits", "Opened pull request", "Opened issue", "Reviewed pull request", "Made 1 commit", "Created repository",
        ])
        #expect(items.map(\.kind) == [.commits, .pullRequest, .issue, .review, .commits, .repository])
        #expect(items.map(\.date) == [
            date("2026-11-09T00:00:00Z"), date("2026-11-08T10:30:00Z"), date("2026-11-07T09:00:00Z"),
            date("2026-11-06T09:00:00Z"), date("2026-11-02T00:00:00Z"), date("2026-11-01T08:00:00Z"),
        ])
    }

    @Test func rowsCarryTheRepositoryTheDetailAndTheLink() throws {
        let items = try ActivityParser.parse(data(reply))

        #expect(items[0].repo == "octocat/hello")
        #expect(items[0].detail == nil)
        #expect(items[0].subtitle == "octocat/hello")
        #expect(items[0].url?.absoluteString == "https://github.com/octocat/hello")

        #expect(items[1].detail == "#12 Fix the crash")
        #expect(items[1].subtitle == "octocat/hello · #12 Fix the crash")
        #expect(items[1].url?.absoluteString == "https://github.com/octocat/hello/pull/12")

        #expect(items[2].url?.absoluteString == "https://github.com/octocat/hello/issues/5")
        #expect(items[3].repo == "friend/app")
        #expect(items[5].url?.absoluteString == "https://github.com/octocat/new-thing")
    }

    @Test func anEmptyCollectionGivesNoRows() throws {
        let empty = """
        {"data":{"viewer":{"contributionsCollection":{"commitContributionsByRepository":[],
          "pullRequestContributions":{"nodes":[]},"issueContributions":{"nodes":[]},
          "pullRequestReviewContributions":{"nodes":[]},"repositoryContributions":{"nodes":[]}}}}}
        """
        #expect(try ActivityParser.parse(data(empty)).isEmpty)
    }

    @Test func missingListsAndNullEntriesAreTolerated() throws {
        let odd = """
        {"data":{"viewer":{"contributionsCollection":{
          "commitContributionsByRepository":[null,{"repository":null,"contributions":null}],
          "pullRequestContributions":{"nodes":[null,{"occurredAt":"2026-11-08T10:30:00Z","pullRequest":null}]},
          "issueContributions":null}}}}
        """
        #expect(try ActivityParser.parse(data(odd)).isEmpty)
    }

    @Test func aRowWithSomethingWrongIsLeftOutAndTheRestStay() throws {
        let mixed = """
        {"data":{"viewer":{"contributionsCollection":{
          "commitContributionsByRepository":[
            {"repository":{"nameWithOwner":"octocat/hello","url":"https://github.com/octocat/hello"},
             "contributions":{"nodes":[
               {"commitCount":0,"occurredAt":"2026-11-09T00:00:00Z"},
               {"commitCount":2,"occurredAt":"not a date"},
               {"commitCount":2,"occurredAt":"2026-11-08T00:00:00Z"}]}},
            {"repository":{"nameWithOwner":"no slash here","url":null},
             "contributions":{"nodes":[{"commitCount":9,"occurredAt":"2026-11-09T00:00:00Z"}]}}]
        }}}}
        """
        let items = try ActivityParser.parse(data(mixed))
        #expect(items.count == 1)
        #expect(items[0].action == "Made 2 commits")
    }

    @Test func anAddressOutsideGitHubIsReplacedByTheRepositoryAddress() throws {
        let tricky = """
        {"data":{"viewer":{"contributionsCollection":{
          "pullRequestContributions":{"nodes":[
            {"occurredAt":"2026-11-08T10:30:00Z","pullRequest":{"title":"Hi","number":1,
              "url":"https://evil.example.com/pull/1","repository":{"nameWithOwner":"octocat/hello"}}}]}
        }}}}
        """
        let items = try ActivityParser.parse(data(tricky))
        #expect(items.count == 1)
        #expect(items[0].url?.absoluteString == "https://github.com/octocat/hello")
    }

    @Test func aTitleIsCleanedBeforeItIsShown() throws {
        let messy = """
        {"data":{"viewer":{"contributionsCollection":{
          "issueContributions":{"nodes":[
            {"occurredAt":"2026-11-08T10:30:00Z","issue":{"title":"Line one\\nline   two","number":7,
              "url":"https://github.com/octocat/hello/issues/7","repository":{"nameWithOwner":"octocat/hello"}}}]}
        }}}}
        """
        let items = try ActivityParser.parse(data(messy))
        #expect(items.first?.detail == "#7 Line one line two")
    }

    @Test func aPullRequestWithoutATitleStillShowsItsNumber() throws {
        let bare = """
        {"data":{"viewer":{"contributionsCollection":{
          "pullRequestContributions":{"nodes":[
            {"occurredAt":"2026-11-08T10:30:00Z","pullRequest":{"title":null,"number":3,
              "url":"https://github.com/octocat/hello/pull/3","repository":{"nameWithOwner":"octocat/hello"}}}]}
        }}}}
        """
        #expect(try ActivityParser.parse(data(bare)).first?.detail == "#3")
    }

    @Test func datesWithFractionalSecondsAreRead() throws {
        let fractional = """
        {"data":{"viewer":{"contributionsCollection":{
          "repositoryContributions":{"nodes":[
            {"occurredAt":"2026-11-01T08:00:00.000Z","repository":{"nameWithOwner":"octocat/new-thing","url":null}}]}
        }}}}
        """
        let items = try ActivityParser.parse(data(fractional))
        #expect(items.first?.date == date("2026-11-01T08:00:00Z"))
        #expect(items.first?.url?.absoluteString == "https://github.com/octocat/new-thing")
    }

    // MARK: Errors

    @Test func errorsInsideTheReplyAreReported() {
        let limited = #"{"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded"}]}"#
        #expect(throws: GitHubError.rateLimited(retryAfter: nil)) { try ActivityParser.parse(data(limited)) }

        let other = #"{"errors":[{"type":"NOT_FOUND","message":"Could not resolve to a User."}]}"#
        #expect(throws: GitHubError.graphQL("Could not resolve to a User.")) { try ActivityParser.parse(data(other)) }
    }

    @Test func aReplyWithoutTheCollectionIsRejected() {
        for text in ["", "not json", "[]", #"{"data":null}"#, #"{"data":{"viewer":null}}"#, #"{"data":{"viewer":{}}}"#] {
            #expect(throws: GitHubError.unexpectedResponse, "\(text)") { try ActivityParser.parse(data(text)) }
        }
    }

    // MARK: Links and text

    @Test func onlyPlainGitHubAddressesAreLinks() {
        #expect(GitHubLink.validated("https://github.com/octocat/hello")?.absoluteString == "https://github.com/octocat/hello")
        #expect(GitHubLink.validated("HTTPS://GitHub.com/octocat/hello") != nil)

        let refused = [
            nil,
            "",
            "http://github.com/octocat/hello",
            "https://github.com.evil.example/octocat/hello",
            "https://evilgithub.com/octocat/hello",
            "https://gist.github.com/octocat/1",
            "https://user:pass@github.com/octocat/hello",
            "https://github.com:8443/octocat/hello",
            "javascript:alert(1)",
            "file:///etc/hosts",
            "github.com/octocat/hello",
            "https://github.com/" + String(repeating: "a", count: 400),
        ]
        for text in refused {
            #expect(GitHubLink.validated(text) == nil, "\(text ?? "nil")")
        }
    }

    @Test func repositoryNamesAreChecked() {
        #expect(ActivityText.repoName("octocat/hello") == "octocat/hello")
        #expect(ActivityText.repoName("my-org/my_repo.js") == "my-org/my_repo.js")

        for bad in [nil, "", "octocat", "/hello", "octocat/", "a/b/c", "octo cat/hello", "octocat/héllo", "octocat/hello?x=1", "octocat/hello\n",
                    String(repeating: "a", count: 80) + "/" + String(repeating: "b", count: 80)] {
            #expect(ActivityText.repoName(bad) == nil, "\(bad ?? "nil")")
        }
    }

    @Test func titlesAreCleaned() {
        #expect(ActivityText.title("Fix the crash") == "Fix the crash")
        #expect(ActivityText.title("  spaced \t out \r\n title ") == "spaced out title")
        #expect(ActivityText.title("") == nil)
        #expect(ActivityText.title("   \n ") == nil)
        #expect(ActivityText.title(nil) == nil)
        // Characters that flip the direction of text are dropped.
        #expect(ActivityText.title("abc\u{202E}def\u{2066}") == "abcdef")
        // Emoji and other languages are left alone.
        #expect(ActivityText.title("Fix 🐛 in ロード") == "Fix 🐛 in ロード")
    }

    @Test func longTitlesAreCut() throws {
        let long = String(repeating: "x", count: 500)
        let cut = try #require(ActivityText.title(long))
        #expect(cut.count == 120)
        #expect(cut.hasSuffix("…"))
        #expect(ActivityText.title(String(repeating: "x", count: 120))?.count == 120)
        #expect(ActivityText.title(String(repeating: "x", count: 120))?.hasSuffix("…") == false)
    }

    // MARK: Putting pages together

    @Test func aRowThatIsInBothListsIsKeptOnce() {
        let merged = ActivityMerge.appending([item("b", "2026-11-05T00:00:00Z"), item("c", "2026-11-04T00:00:00Z")],
                                             to: [item("a", "2026-11-06T00:00:00Z"), item("b", "2026-11-05T00:00:00Z")])
        #expect(merged.map(\.id) == ["a", "b", "c"])
    }

    @Test func theListIsAlwaysNewestFirstAndStable() {
        let same = "2026-11-05T00:00:00Z"
        let merged = ActivityMerge.appending([item("z", same), item("y", same), item("old", "2026-10-01T00:00:00Z")],
                                             to: [item("new", "2026-11-09T00:00:00Z")])
        #expect(merged.map(\.id) == ["new", "y", "z", "old"])
    }

    @Test func aRefreshReplacesWhatItCoversAndKeepsWhatIsOlder() {
        let existing = [
            item("deleted", "2026-11-08T00:00:00Z"),
            item("kept-in-range", "2026-11-05T00:00:00Z"),
            item("older-1", "2026-09-20T00:00:00Z"),
            item("older-2", "2026-08-20T00:00:00Z"),
        ]
        let fresh = [item("brand-new", "2026-11-09T00:00:00Z"), item("kept-in-range", "2026-11-05T00:00:00Z")]
        let merged = ActivityMerge.refreshing(existing, with: fresh, coveredBack: date("2026-10-10T00:00:00Z"))
        #expect(merged.map(\.id) == ["brand-new", "kept-in-range", "older-1", "older-2"])
    }

    // MARK: Which stretch of time to ask about

    @Test func theFirstWindowIsThirtyDays() throws {
        let now = date("2026-11-10T12:00:00Z")
        let limit = now.addingTimeInterval(-365 * 86_400)
        let window = try #require(ActivityWindows.window(endingAt: now, notBefore: limit))
        #expect(window.to == now)
        #expect(window.from == date("2026-10-11T12:00:00Z"))
    }

    @Test func windowsFollowEachOtherWithoutAGapOrAnOverlap() throws {
        let now = date("2026-11-10T12:00:00Z")
        let limit = now.addingTimeInterval(-365 * 86_400)
        let first = try #require(ActivityWindows.window(endingAt: now, notBefore: limit))
        let next = try #require(ActivityWindows.window(endingAt: first.from.addingTimeInterval(-1), notBefore: limit))
        #expect(next.to == first.from.addingTimeInterval(-1))
        #expect(next.to.timeIntervalSince(next.from) == 30 * 86_400)
    }

    @Test func theLastWindowStopsAtTheLimitAndThenThereIsNothingOlder() throws {
        let limit = date("2026-01-01T00:00:00Z")
        let end = date("2026-01-11T00:00:00Z")
        let last = try #require(ActivityWindows.window(endingAt: end, notBefore: limit))
        #expect(last.from == limit)
        #expect(last.to == end)
        #expect(ActivityWindows.window(endingAt: last.from.addingTimeInterval(-1), notBefore: limit) == nil)
        #expect(ActivityWindows.window(endingAt: limit, notBefore: limit) == nil)
    }

    @Test func aYearTakesThirteenWindows() {
        let now = date("2026-11-10T12:00:00Z")
        let limit = now.addingTimeInterval(-365 * 86_400)
        var end = now
        var count = 0
        while let window = ActivityWindows.window(endingAt: end, notBefore: limit) {
            count += 1
            end = window.from.addingTimeInterval(-1)
            if count > 50 { break }
        }
        #expect(count == 13)
    }

    // MARK: The request

    @Test func theQueryAsksForTheFiveKindsAndNothingElse() {
        let request = ActivityQuery.make(from: date("2026-10-11T12:00:00Z"), to: date("2026-11-10T12:00:00Z"))
        #expect(request.variables == ["from": "2026-10-11T12:00:00Z", "to": "2026-11-10T12:00:00Z"])
        #expect(request.query.hasPrefix("query($from: DateTime!, $to: DateTime!) { viewer { contributionsCollection(from: $from, to: $to) {"))
        for field in ["commitContributionsByRepository(maxRepositories: 25)", "pullRequestContributions(first: 50)",
                      "issueContributions(first: 50)", "pullRequestReviewContributions(first: 50)",
                      "repositoryContributions(first: 50)", "contributions(first: 31)"] {
            #expect(request.query.contains(field), "\(field)")
        }
        // No commit messages, no file names, no code.
        for forbidden in ["message", "oid", "diff", "patch", "body", "file"] {
            #expect(!request.query.lowercased().contains(forbidden), "\(forbidden)")
        }
    }

    @Test func theQueryBracesAreBalanced() {
        let query = ActivityQuery.make(from: Date(timeIntervalSince1970: 0), to: Date(timeIntervalSince1970: 86_400)).query
        #expect(query.filter { $0 == "{" }.count == query.filter { $0 == "}" }.count)
        #expect(!query.contains("\\"))
        #expect(!query.contains("\n"))
    }

    // MARK: Dates on the rows

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func label(_ iso: String, now: String = "2026-11-10T15:00:00Z") -> String {
        ActivityDateLabel.text(for: date(iso), now: date(now), calendar: calendar, locale: Locale(identifier: "en_US"))
    }

    @Test func recentDatesReadInWords() {
        #expect(label("2026-11-10T01:00:00Z") == "Today")
        #expect(label("2026-11-10T23:00:00Z") == "Today")   // a time later today is still today
        #expect(label("2026-11-11T09:00:00Z") == "Today")   // a clock that is slightly off never shows the future
        #expect(label("2026-11-09T23:59:00Z") == "Yesterday")
        #expect(label("2026-11-08T08:00:00Z") == "2 days ago")
        #expect(label("2026-11-04T08:00:00Z") == "6 days ago")
        #expect(label("2026-11-03T08:00:00Z") == "1 week ago")
        #expect(label("2026-10-27T08:00:00Z") == "2 weeks ago")
        #expect(label("2026-10-12T08:00:00Z") == "4 weeks ago")
    }

    @Test func olderDatesShowTheDay() {
        #expect(label("2026-10-11T08:00:00Z") == "Oct 11")
        #expect(label("2026-01-05T08:00:00Z") == "Jan 5")
        #expect(label("2025-12-20T08:00:00Z") == "Dec 20, 2025")
    }
}
