import Foundation

/// Counts today's commits from each saved project's own log file (`logs/HEAD`), the same file GitRepositoryService
/// reads for "last commit". Like the rest of Gitzy's git reading it never starts a git process and never writes anything.
///
/// Only projects with a GitHub remote are counted, because a commit in a project that is not on GitHub can never reach
/// the graph. A commit made on another computer only shows up here once it has been pulled.
nonisolated enum TodayCommits {

    /// How much of the end of the log is read. The newest entries are at the end, and this holds hundreds of them.
    private static let logWindow: UInt64 = 65_536

    /// The saved projects at `paths`, counted together. Commits made at or after `start` count.
    static func summary(forProjectsAt paths: [String], since start: Date) -> LocalToday {
        var commits = 0
        var projects = 0
        for path in paths {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            guard let gitDir = GitRepositoryService.gitDirectory(forRepoAt: folder),
                  GitRemote.githubURL(forGitDirectory: gitDir) != nil
            else { continue }
            let found = count(inGitDirectory: gitDir, since: start)
            if found > 0 {
                commits += found
                projects += 1
            }
        }
        return LocalToday(commits: commits, projects: projects)
    }

    static func count(inGitDirectory gitDir: URL, since start: Date) -> Int {
        let log = gitDir.appendingPathComponent("logs").appendingPathComponent("HEAD")
        guard let handle = try? FileHandle(forReadingFrom: log) else { return 0 }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return 0 }
        let from = size > logWindow ? size - logWindow : 0
        guard (try? handle.seek(toOffset: from)) != nil, let data = try? handle.readToEnd() else { return 0 }

        var text = String(decoding: data, as: UTF8.self)
        // Reading from the middle of the file starts part way through a line, so drop that first piece.
        if from > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return count(inReflog: text, since: start)
    }

    /// The number of new commits in this log text that were made at or after `start`.
    /// A line looks like: `<old id> <new id> Name <email> <unix time> <zone>` + tab + `commit: message`.
    /// Only commits count. Pulls, merges of other people's work, rebases and checkouts are not the person's own new work.
    static func count(inReflog reflog: String, since start: Date) -> Int {
        let earliest = start.timeIntervalSince1970
        var total = 0
        for line in reflog.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, isNewCommit(parts[1]) else { continue }
            // The unix time is the second word from the end, just before the time zone ("+0800").
            let words = parts[0].split(separator: " ")
            guard words.count >= 2, let seconds = TimeInterval(words[words.count - 2]) else { continue }
            if seconds >= earliest { total += 1 }
        }
        return total
    }

    /// "commit: ...", "commit (initial): ..." and "commit (merge): ...". An amend is the same work again, so it is not counted.
    static func isNewCommit(_ message: Substring) -> Bool {
        message.hasPrefix("commit:") || message.hasPrefix("commit (initial):") || message.hasPrefix("commit (merge):")
    }
}
