import Foundation
import Testing
@testable import Gitzy

/// GitHub replies written out by hand, for the profile fields and the this-year count.
/// None of them contains a token or any other secret.
nonisolated struct GitHubProfileTests {

    private func data(_ json: String) -> Data { Data(json.utf8) }

    private func reply(profile: String) -> String {
        """
        {"data":{"viewer":{\(profile),"contributionsCollection":{"contributionCalendar":{
          "totalContributions":3,
          "weeks":[{"contributionDays":[
            {"date":"2026-10-26","contributionCount":3,"contributionLevel":"SECOND_QUARTILE","weekday":1}
          ]}]}}}}}
        """
    }

    // MARK: Parsing the profile

    @Test func readsTheNameAndPictureAddress() throws {
        let json = reply(profile: #""login":"octocat","name":"The Octocat","avatarUrl":"https://avatars.githubusercontent.com/u/583231?v=4&s=96""#)
        let parsed = try GitHubParser.parse(data(json))
        #expect(parsed.login == "octocat")
        #expect(parsed.name == "The Octocat")
        #expect(parsed.avatarURL == "https://avatars.githubusercontent.com/u/583231?v=4&s=96")
    }

    @Test func theProfileFieldsAreNotMistakenForCalendars() throws {
        let json = reply(profile: #""login":"octocat","name":"The Octocat","avatarUrl":"https://avatars.githubusercontent.com/u/1""#)
        let parsed = try GitHubParser.parse(data(json))
        #expect(Set(parsed.calendars.keys) == ["contributionsCollection"])
    }

    @Test func aMissingNameIsNil() throws {
        let json = reply(profile: #""login":"octocat","name":null,"avatarUrl":"https://avatars.githubusercontent.com/u/1""#)
        #expect(try GitHubParser.parse(data(json)).name == nil)
    }

    @Test func aBlankNameIsNil() throws {
        let json = reply(profile: #""login":"octocat","name":"   ","avatarUrl":"https://avatars.githubusercontent.com/u/1""#)
        #expect(try GitHubParser.parse(data(json)).name == nil)
    }

    @Test func aNameIsTrimmed() throws {
        let json = reply(profile: #""login":"octocat","name":"  The Octocat \n","avatarUrl":null"#)
        #expect(try GitHubParser.parse(data(json)).name == "The Octocat")
    }

    @Test func anOldStyleReplyWithoutProfileFieldsStillParses() throws {
        let json = reply(profile: #""login":"octocat""#)
        let parsed = try GitHubParser.parse(data(json))
        #expect(parsed.login == "octocat")
        #expect(parsed.name == nil)
        #expect(parsed.avatarURL == nil)
    }

    @Test func aLoginOnlyReplyHasNoProfile() throws {
        let parsed = try GitHubParser.parse(data(#"{"data":{"viewer":{"login":"octocat"}}}"#))
        #expect(parsed.name == nil)
        #expect(parsed.avatarURL == nil)
        #expect(parsed.calendars.isEmpty)
    }

    @Test func theContributionsRequestAsksForTheProfile() {
        #expect(GitHubQueries.lastYear.contains("name"))
        #expect(GitHubQueries.lastYear.contains("avatarUrl(size: 96)"))
        #expect(GitHubQueries.lastYear.contains("contributionsCollection { contributionCalendar"))
    }

    @Test func theTokenCheckStaysMinimal() {
        #expect(GitHubQueries.viewerLogin == "query { viewer { login } }")
    }

    // MARK: Contributions this year

    private func snapshot(_ days: [[(String, Int)]]) -> ContributionSnapshot {
        ContributionSnapshot(
            login: "octocat",
            name: nil,
            avatarURL: nil,
            weeks: days.map { week in
                week.map { ContributionDay(date: $0.0, count: $0.1, level: .none, weekday: 0) }
            },
            totalContributions: days.joined().reduce(0) { $0 + $1.1 },
            currentStreak: 0,
            fetchedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func onlyDaysOfTheNewestYearAreCounted() {
        let shot = snapshot([
            [("2025-12-30", 5), ("2025-12-31", 7)],
            [("2026-01-01", 2), ("2026-01-02", 3)],
            [("2026-10-25", 4)]
        ])
        #expect(shot.currentYear == 2026)
        #expect(shot.contributionsThisYear == 9)
        #expect(shot.totalContributions == 21)   // the 12-month total is untouched
    }

    @Test func aGraphInsideOneYearCountsEverything() {
        let shot = snapshot([[("2026-03-01", 1), ("2026-03-02", 0)], [("2026-03-03", 6)]])
        #expect(shot.contributionsThisYear == 7)
    }

    @Test func theFirstDayOfTheYearCountsAsTheNewYear() {
        let shot = snapshot([[("2025-12-31", 9)], [("2026-01-01", 1)]])
        #expect(shot.currentYear == 2026)
        #expect(shot.contributionsThisYear == 1)
    }

    @Test func anEmptyGraphHasNoYearAndNoCount() {
        let shot = snapshot([])
        #expect(shot.currentYear == nil)
        #expect(shot.contributionsThisYear == 0)
    }

    @Test func anEmptyLastWeekHasNoYearAndNoCount() {
        let shot = snapshot([[("2026-01-01", 3)], []])
        #expect(shot.currentYear == nil)
        #expect(shot.contributionsThisYear == 0)
    }
}
