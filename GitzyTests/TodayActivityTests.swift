import Foundation
import Testing
@testable import Gitzy

/// The dot on the profile picture: today from the graph, today from this Mac's git logs, and the words for the card.
/// Repository log files are written out by hand. The names and addresses in them are made up.
nonisolated struct TodayActivityTests {

    private let nobody = "0000000000000000000000000000000000000000"
    private let someone = "1111111111111111111111111111111111111111"

    /// One line of `.git/logs/HEAD`: ids, author, unix time, zone, a tab, then the message.
    private func line(_ time: Int, _ message: String, zone: String = "+0800") -> String {
        "\(nobody) \(someone) Ada Example <ada@example.com> \(time) \(zone)\t\(message)"
    }

    private func reflog(_ lines: String...) -> String { lines.joined(separator: "\n") + "\n" }

    private func date(_ seconds: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }

    private let startOfToday = 1_000_000

    private func day(_ text: String, _ count: Int) -> ContributionDay {
        ContributionDay(date: text, count: count, level: count > 0 ? .second : .none, weekday: 0)
    }

    private func utc() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    // MARK: The colour of the dot

    @Test func greyWhenThereIsNothingToday() {
        #expect(TodayActivity(graphCount: 0, local: .none).level == .quiet)
    }

    @Test func orangeWhenThereAreCommitsHereButTheGraphIsEmpty() {
        #expect(TodayActivity(graphCount: 0, local: LocalToday(commits: 2, projects: 1)).level == .notOnGitHubYet)
    }

    @Test func greenWhenTheGraphHasAnythingForToday() {
        #expect(TodayActivity(graphCount: 1, local: .none).level == .onGitHub)
        #expect(TodayActivity(graphCount: 4, local: LocalToday(commits: 9, projects: 3)).level == .onGitHub)
    }

    // MARK: The words

    @Test func countsReadInPlainWords() {
        #expect(TodayActivity(graphCount: 0, local: .none).graphText == "No contributions")
        #expect(TodayActivity(graphCount: 1, local: .none).graphText == "1 contribution")
        #expect(TodayActivity(graphCount: 12, local: .none).graphText == "12 contributions")

        #expect(TodayActivity(graphCount: 0, local: .none).localText == "No commits")
        #expect(TodayActivity(graphCount: 0, local: LocalToday(commits: 1, projects: 1)).localText == "1 commit in 1 project")
        #expect(TodayActivity(graphCount: 0, local: LocalToday(commits: 5, projects: 2)).localText == "5 commits in 2 projects")
        #expect(TodayActivity(graphCount: 0, local: LocalToday(commits: 2, projects: 1)).localText == "2 commits in 1 project")
    }

    @Test func eachStateHasItsOwnHeadline() {
        let headlines = [
            TodayActivity(graphCount: 0, local: .none).headline,
            TodayActivity(graphCount: 0, local: LocalToday(commits: 1, projects: 1)).headline,
            TodayActivity(graphCount: 1, local: .none).headline,
        ]
        #expect(Set(headlines).count == 3)
        #expect(headlines[1].contains("not on your graph yet"))
    }

    // MARK: Today in the graph

    @Test func todaysSquareIsFoundByItsDate() {
        let weeks = [
            [day("2026-11-08", 0), day("2026-11-09", 2)],
            [day("2026-11-10", 5), day("2026-11-11", 3)],
        ]
        #expect(TodayActivity.graphCount(in: weeks, on: "2026-11-11") == 3)
        #expect(TodayActivity.graphCount(in: weeks, on: "2026-11-09") == 2)
    }

    @Test func aDayThatIsNotInTheGraphCountsAsNothing() {
        let weeks = [[day("2026-11-10", 5)]]
        #expect(TodayActivity.graphCount(in: weeks, on: "2026-11-12") == 0)
        #expect(TodayActivity.graphCount(in: [], on: "2026-11-12") == 0)
    }

    @Test func theDayIsWrittenTheWayGitHubWritesIt() {
        let instant = ISO8601DateFormatter().date(from: "2026-01-05T10:00:00Z")!
        #expect(TodayActivity.dayString(for: instant, calendar: utc()) == "2026-01-05")
    }

    @Test func theDayFollowsTheTimeZoneOfTheCalendar() {
        // 23:30 in UTC on the 11th is already the 12th in Manila.
        let instant = ISO8601DateFormatter().date(from: "2026-11-11T23:30:00Z")!
        var manila = Calendar(identifier: .gregorian)
        manila.timeZone = TimeZone(identifier: "Asia/Manila")!
        #expect(TodayActivity.dayString(for: instant, calendar: utc()) == "2026-11-11")
        #expect(TodayActivity.dayString(for: instant, calendar: manila) == "2026-11-12")
    }

    @Test func nothingIsKnownBeforeTheGraphHasLoaded() {
        #expect(TodayActivity.make(weeks: nil, local: .none) == nil)
    }

    @Test func todayIsBuiltFromTheGraphAndThisMac() {
        let weeks = [[day("2026-11-10", 5), day("2026-11-11", 0)]]
        let now = ISO8601DateFormatter().date(from: "2026-11-11T09:00:00Z")!
        let local = LocalToday(commits: 2, projects: 1)
        let today = TodayActivity.make(weeks: weeks, local: local, now: now, calendar: utc())
        #expect(today == TodayActivity(graphCount: 0, local: local))
        #expect(today?.level == .notOnGitHubYet)
    }

    // MARK: Commits in a log

    @Test func onlyCommitsFromTodayCount() {
        let text = reflog(
            line(startOfToday - 5_000, "commit: yesterday"),
            line(startOfToday + 100, "commit: this morning"),
            line(startOfToday + 200, "commit: this afternoon")
        )
        #expect(TodayCommits.count(inReflog: text, since: date(startOfToday)) == 2)
    }

    @Test func aCommitAtTheVeryStartOfTheDayCounts() {
        let text = reflog(line(startOfToday, "commit: midnight"))
        #expect(TodayCommits.count(inReflog: text, since: date(startOfToday)) == 1)
        #expect(TodayCommits.count(inReflog: text, since: date(startOfToday + 1)) == 0)
    }

    @Test func firstCommitsAndMergeCommitsCount() {
        let text = reflog(
            line(startOfToday + 1, "commit (initial): first"),
            line(startOfToday + 2, "commit (merge): Merge branch 'feature'")
        )
        #expect(TodayCommits.count(inReflog: text, since: date(startOfToday)) == 2)
    }

    @Test func amendsPullsAndOtherMovesAreNotNewWork() {
        let text = reflog(
            line(startOfToday + 1, "commit (amend): same work again"),
            line(startOfToday + 2, "pull: Fast-forward"),
            line(startOfToday + 3, "merge main: Fast-forward"),
            line(startOfToday + 4, "rebase (finish): returning to refs/heads/main"),
            line(startOfToday + 5, "cherry-pick: someone else's commit"),
            line(startOfToday + 6, "checkout: moving from main to feature"),
            line(startOfToday + 7, "reset: moving to HEAD~1"),
            line(startOfToday + 8, "clone: from https://github.com/octocat/hello.git")
        )
        #expect(TodayCommits.count(inReflog: text, since: date(startOfToday)) == 0)
    }

    @Test func brokenLinesAreSkippedNotTrusted() {
        let text = [
            "",
            "no tab in this line at all",
            "\tcommit: nothing before the tab",
            "\(nobody) \(someone) Ada <a@b.c> notanumber +0800\tcommit: bad time",
            line(startOfToday + 10, "commit: the one good line"),
        ].joined(separator: "\n")
        #expect(TodayCommits.count(inReflog: text, since: date(startOfToday)) == 1)
    }

    @Test func anEmptyLogHasNoCommits() {
        #expect(TodayCommits.count(inReflog: "", since: date(startOfToday)) == 0)
        #expect(TodayCommits.count(inReflog: "\n\n", since: date(startOfToday)) == 0)
    }

    @Test func theKindOfCommitMessageIsRecognised() {
        #expect(TodayCommits.isNewCommit("commit: a"))
        #expect(TodayCommits.isNewCommit("commit (initial): a"))
        #expect(TodayCommits.isNewCommit("commit (merge): a"))
        #expect(!TodayCommits.isNewCommit("commit (amend): a"))
        #expect(!TodayCommits.isNewCommit("commitment: a"))
        #expect(!TodayCommits.isNewCommit("pull: a"))
        #expect(!TodayCommits.isNewCommit(""))
    }

    // MARK: Projects on disk

    private let githubConfig = "[core]\n\tbare = false\n[remote \"origin\"]\n\turl = https://github.com/octocat/hello.git\n"
    private let localOnlyConfig = "[core]\n\tbare = false\n"

    @Test func onlyProjectsOnGitHubAreCountedAndAddedUp() throws {
        let temp = try TempFolder()
        let todayLog = reflog(line(startOfToday + 10, "commit: a"), line(startOfToday + 20, "commit: b"))
        let otherLog = reflog(line(startOfToday + 30, "commit: c"))

        let one = try temp.repo("one")
        try temp.write(githubConfig, to: "one/.git/config")
        try temp.write(todayLog, to: "one/.git/logs/HEAD")

        let two = try temp.repo("two")
        try temp.write(githubConfig, to: "two/.git/config")
        try temp.write(otherLog, to: "two/.git/logs/HEAD")

        let notOnGitHub = try temp.repo("local-only")
        try temp.write(localOnlyConfig, to: "local-only/.git/config")
        try temp.write(todayLog, to: "local-only/.git/logs/HEAD")

        let quiet = try temp.repo("quiet")
        try temp.write(githubConfig, to: "quiet/.git/config")
        try temp.write(reflog(line(startOfToday - 99_999, "commit: long ago")), to: "quiet/.git/logs/HEAD")

        let paths = [one, two, notOnGitHub, quiet].map(\.path)
        let summary = TodayCommits.summary(forProjectsAt: paths, since: date(startOfToday))
        #expect(summary == LocalToday(commits: 3, projects: 2))
    }

    @Test func missingFoldersAndNonRepositoriesAreIgnored() throws {
        let temp = try TempFolder()
        let plain = try temp.folder("not-a-repo")
        let noLog = try temp.repo("no-log")
        try temp.write(githubConfig, to: "no-log/.git/config")

        let paths = [temp.root.appendingPathComponent("gone").path, plain.path, noLog.path]
        #expect(TodayCommits.summary(forProjectsAt: paths, since: date(startOfToday)) == LocalToday.none)
        #expect(TodayCommits.summary(forProjectsAt: [], since: date(startOfToday)) == LocalToday.none)
    }

    @Test func aProjectWhoseOnlyRemoteIsNotGitHubIsIgnored() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("elsewhere")
        try temp.write("[remote \"origin\"]\n\turl = https://gitlab.com/octocat/hello.git\n", to: "elsewhere/.git/config")
        try temp.write(reflog(line(startOfToday + 10, "commit: a")), to: "elsewhere/.git/logs/HEAD")
        #expect(TodayCommits.summary(forProjectsAt: [repo.path], since: date(startOfToday)) == LocalToday.none)
    }
}
