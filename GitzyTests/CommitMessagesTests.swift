import Foundation
import Testing
@testable import Gitzy

nonisolated struct CommitMessagesTests {
    private func date(_ hours: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(hours * 3_600)) }

    private func day(_ hours: Int, count: Int, repo: String = "ada/demo") -> ActivityItem {
        ActivityItem(id: "c|\(repo)|\(hours)", kind: .commits, action: "Made \(count) commit", repo: repo,
                     detail: nil, date: date(hours), url: nil, commitCount: count)
    }

    @Test func aSingleCommitDayGetsItsMessage() {
        let items = [day(100, count: 1)]
        let found = ["ada/demo": [CommitMessages.Found(date: date(96), headline: "Fix the crash")]]
        let result = CommitMessages.attach(to: items, found: found)
        #expect(result[0].commitMessage == "Fix the crash")
        #expect(result[0].action == "Fix the crash")
    }

    @Test func commitsAreHandedOutNewestFirstAndBusyDaysUseTheirShare() {
        let items = [day(200, count: 1), day(100, count: 2), day(50, count: 1)]
        let found = ["ada/demo": [
            CommitMessages.Found(date: date(198), headline: "Newest"),
            CommitMessages.Found(date: date(102), headline: "Busy day, later"),
            CommitMessages.Found(date: date(101), headline: "Busy day, earlier"),
            CommitMessages.Found(date: date(52), headline: "Oldest")
        ]]
        let result = CommitMessages.attach(to: items, found: found)
        #expect(result[0].commitMessage == "Newest")
        #expect(result[1].commitMessage == nil)
        #expect(result[2].commitMessage == "Oldest")
    }

    @Test func commitsThatDoNotFitTheCountsAreNotUsed() {
        let items = [day(100, count: 1)]
        let found = ["ada/demo": [CommitMessages.Found(date: date(10), headline: "Far away")]]
        #expect(CommitMessages.attach(to: items, found: found)[0].commitMessage == nil)
    }

    @Test func tooFewCommitsFoundLeavesTheRowAlone() {
        let items = [day(100, count: 2)]
        let found = ["ada/demo": [CommitMessages.Found(date: date(100), headline: "Only one")]]
        #expect(CommitMessages.attach(to: items, found: found) == items)
    }

    @Test func theQueryNamesEachRepositoryAndRefusesAnOddID() {
        let query = CommitMessages.query(viewerID: "U_abc", repositories: ["ada/demo"], from: date(0), to: date(48))
        #expect(query?.contains("owner: \"ada\", name: \"demo\"") == true)
        #expect(CommitMessages.query(viewerID: "x\" }", repositories: ["ada/demo"], from: date(0), to: date(48)) == nil)
    }
}
