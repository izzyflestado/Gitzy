import Foundation
import Testing
@testable import Gitzy

/// Repository log files written out by hand. The names and addresses in them are made up.
nonisolated struct GitActivityTests {

    private let nobody = "0000000000000000000000000000000000000000"
    private let someone = "1111111111111111111111111111111111111111"

    /// One line of `.git/logs/HEAD`: ids, author, unix time, zone, a tab, then the message.
    private func line(_ time: Int, _ message: String, zone: String = "+0800") -> String {
        "\(nobody) \(someone) Ada Example <ada@example.com> \(time) \(zone)\t\(message)"
    }

    private func date(_ seconds: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(seconds)) }

    // MARK: Reading a log

    @Test func theNewestCommitLineWins() {
        let log = [
            line(1_000, "commit (initial): first"),
            line(2_000, "commit: second"),
            line(3_000, "commit: third")
        ].joined(separator: "\n") + "\n"
        #expect(GitRepositoryService.parseLastActivity(reflog: log) == date(3_000))
    }

    @Test func switchingBranchesIsNotActivity() {
        let log = [
            line(1_000, "commit: real work"),
            line(2_000, "checkout: moving from main to feature"),
            line(3_000, "checkout: moving from feature to main")
        ].joined(separator: "\n")
        #expect(GitRepositoryService.parseLastActivity(reflog: log) == date(1_000))
    }

    @Test func eachKindOfActivityCounts() {
        for message in [
            "commit (initial): a", "commit: a", "commit (amend): a", "commit (merge): a",
            "merge main: Fast-forward", "pull: Fast-forward", "pull --rebase (finish): returning to refs/heads/main",
            "cherry-pick: a", "revert: a", "rebase (finish): returning to refs/heads/main", "clone: from https://example.com/r.git"
        ] {
            #expect(GitRepositoryService.parseLastActivity(reflog: line(42, message)) == date(42), "\(message)")
        }
    }

    @Test func resetsAndOtherMovesAreNotActivity() {
        for message in ["reset: moving to HEAD~1", "checkout: moving from a to b", "branch: Created from HEAD", "stash: something"] {
            #expect(GitRepositoryService.parseLastActivity(reflog: line(42, message)) == nil, "\(message)")
        }
    }

    @Test func anEmptyLogHasNoActivity() {
        #expect(GitRepositoryService.parseLastActivity(reflog: "") == nil)
        #expect(GitRepositoryService.parseLastActivity(reflog: "\n\n") == nil)
    }

    @Test func brokenLinesAreSkippedNotTrusted() {
        let log = [
            line(1_000, "commit: good"),
            "no tab on this line at all",
            "a b c\tcommit: too few words",
            "\(nobody) \(someone) Ada <a@example.com> notanumber +0800\tcommit: bad time"
        ].joined(separator: "\n")
        #expect(GitRepositoryService.parseLastActivity(reflog: log) == date(1_000))
    }

    @Test func aNameWithSpacesAndBracketsStillParses() {
        let odd = "\(nobody) \(someone) Dr. Ada B. Example <ada@example.com> 7777 -0500\tcommit: x"
        #expect(GitRepositoryService.parseLastActivity(reflog: odd) == date(7_777))
    }

    @Test func windowsLineEndingsAreFine() {
        let log = [line(1_000, "commit: a"), line(2_000, "commit: b")].joined(separator: "\r\n")
        #expect(GitRepositoryService.parseLastActivity(reflog: log) == date(2_000))
    }

    @Test func aTabInsideTheMessageDoesNotBreakIt() {
        #expect(GitRepositoryService.parseLastActivity(reflog: line(5, "commit: a\tb")) == date(5))
    }

    // MARK: Reading from a real folder

    @Test func readsAProjectsLogFromItsFolder() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("app")
        try temp.write(line(1_000, "commit (initial): a") + "\n" + line(9_000, "commit: b") + "\n", to: "app/.git/logs/HEAD")
        #expect(GitRepositoryService.lastActivity(ofProjectAt: repo.path) == date(9_000))
    }

    @Test func aRepositoryWithoutALogHasNoActivity() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("app")
        #expect(GitRepositoryService.lastActivity(ofProjectAt: repo.path) == nil)
    }

    @Test func aFolderThatIsNotARepositoryHasNoActivity() throws {
        let temp = try TempFolder()
        let folder = try temp.folder("plain")
        #expect(GitRepositoryService.lastActivity(ofProjectAt: folder.path) == nil)
    }

    @Test func aFolderThatDoesNotExistHasNoActivity() throws {
        let temp = try TempFolder()
        #expect(GitRepositoryService.lastActivity(ofProjectAt: temp.root.appendingPathComponent("nope").path) == nil)
    }

    @Test func aWorktreeReadsItsOwnLogThroughTheGitdirPointer() throws {
        let temp = try TempFolder()
        try temp.write("ref: refs/heads/feature\n", to: "store/worktrees/wt/HEAD")
        try temp.write(line(4_000, "commit: in the worktree") + "\n", to: "store/worktrees/wt/logs/HEAD")
        try temp.write("gitdir: \(temp.root.path)/store/worktrees/wt\n", to: "wt-folder/.git")
        let folder = temp.root.appendingPathComponent("wt-folder", isDirectory: true)
        #expect(GitRepositoryService.lastActivity(ofProjectAt: folder.path) == date(4_000))
    }

    @Test func aLongLogIsReadFromItsEnd() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("app")
        // About 200 KB of branch switching, which is far more than the part that is read, then one real commit.
        var lines = (0..<2_000).map { line(1_000 + $0, "checkout: moving from main to branch-number-\($0)-padding-padding-padding") }
        lines.append(line(99_999, "commit: the newest"))
        try temp.write(lines.joined(separator: "\n") + "\n", to: "app/.git/logs/HEAD")
        #expect(GitRepositoryService.lastActivity(ofProjectAt: repo.path) == date(99_999))
    }

    @Test func aCommitOlderThanTheReadWindowIsNotFound() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("app")
        var lines = [line(1_000, "commit: ancient")]
        lines += (0..<2_000).map { line(2_000 + $0, "checkout: moving from main to branch-number-\($0)-padding-padding-padding") }
        try temp.write(lines.joined(separator: "\n") + "\n", to: "app/.git/logs/HEAD")
        #expect(GitRepositoryService.lastActivity(ofProjectAt: repo.path) == nil)
    }
}
