import Foundation
import Testing
@testable import Gitzy

/// Repository log text written out by hand. The names and addresses in them are made up.
nonisolated struct LocalCommitsTests {
    private let nobody = "0000000000000000000000000000000000000000"

    private func line(_ time: Int, _ message: String, id: String = "1111111111111111111111111111111111111111") -> String {
        "\(nobody) \(id) Ada Example <ada@example.com> \(time) +0800\t\(message)"
    }

    private func date(_ seconds: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }

    private func parse(_ lines: [String], since: Int = 0) -> [ActivityItem] {
        LocalCommits.parse(reflog: lines.joined(separator: "\n") + "\n", projectPath: "/p/demo", repo: "ada/demo", since: date(since))
    }

    @Test func eachCommitIsItsOwnRowWithItsMessage() {
        let items = parse([line(1_000, "commit (initial): First"), line(2_000, "commit: Second")])
        #expect(items.map(\.commitMessage) == ["Second", "First"])
        #expect(items.allSatisfy { $0.repo == "ada/demo" && $0.kind == .commits })
    }

    @Test func onlyNewCommitsCount() {
        let items = parse([
            line(1_000, "checkout: moving from main to topic"),
            line(2_000, "pull: Fast-forward"),
            line(3_000, "commit (amend): Same again"),
            line(4_000, "commit (merge): Merge branch topic")
        ])
        #expect(items.map(\.commitMessage) == ["Merge branch topic"])
    }

    @Test func commitsBeforeTheCutoffAreLeftOut() {
        let items = parse([line(1_000, "commit: Old"), line(5_000, "commit: New")], since: 2_000)
        #expect(items.map(\.commitMessage) == ["New"])
    }

    @Test func aMessageWithAColonKeepsItsWholeText() {
        let items = parse([line(1_000, "commit: Fix: the crash")])
        #expect(items.first?.action == "Fix: the crash")
    }

    @Test func twoCommitsAtTheSameSecondAreBothKept() {
        let items = parse([
            line(1_000, "commit: One", id: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
            line(1_000, "commit: Two", id: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
        ])
        #expect(items.count == 2)
    }
}
