import Foundation

/// The commits made on this Mac in the saved projects, one row each, for the Local view of "Recent activity".
/// They come from each project's own log file (`logs/HEAD`), the same file TodayCommits reads. Like the rest of Gitzy's
/// git reading it never starts a git process and never writes anything. Nothing is stored: the log is read each time.
///
/// Every saved project counts, with or without a GitHub remote, and commits that have not been pushed are included.
/// A commit made on another computer only shows up here once it has been pulled.
nonisolated enum LocalCommits {
    /// How much of the end of a log is read. The newest entries are at the end.
    private static let logWindow: UInt64 = 1_048_576

    /// How far back the list reaches.
    static let days = 30

    /// All commits in the saved projects at `paths` made at or after `since`, newest first.
    static func recent(forProjectsAt paths: [String], since: Date) -> [ActivityItem] {
        var items: [ActivityItem] = []
        for path in paths {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            guard let gitDir = GitRepositoryService.gitDirectory(forRepoAt: folder) else { continue }
            let repo = repoName(gitDirectory: gitDir, folder: folder)
            items += commits(inGitDirectory: gitDir, projectPath: path, repo: repo, since: since)
        }
        return ActivityMerge.appending(items, to: [])
    }

    static func commits(inGitDirectory gitDir: URL, projectPath: String, repo: String, since: Date) -> [ActivityItem] {
        let log = gitDir.appendingPathComponent("logs").appendingPathComponent("HEAD")
        guard let handle = try? FileHandle(forReadingFrom: log) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let from = size > logWindow ? size - logWindow : 0
        guard (try? handle.seek(toOffset: from)) != nil, let data = try? handle.readToEnd() else { return [] }
        var text = String(decoding: data, as: UTF8.self)
        // Reading from the middle of the file starts part way through a line, so drop that first piece.
        if from > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return parse(reflog: text, projectPath: projectPath, repo: repo, since: since)
    }

    /// One row per new commit in this log text made at or after `since`.
    /// A line looks like: `<old id> <new id> Name <email> <unix time> <zone>` + tab + `commit: message`.
    static func parse(reflog: String, projectPath: String, repo: String, since: Date) -> [ActivityItem] {
        let earliest = since.timeIntervalSince1970
        var items: [ActivityItem] = []
        for line in reflog.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, TodayCommits.isNewCommit(parts[1]) else { continue }
            let words = parts[0].split(separator: " ")
            // The unix time is the second word from the end, just before the time zone ("+0800").
            // The new commit's id is the second word of the line.
            guard words.count >= 4, let seconds = TimeInterval(words[words.count - 2]), seconds >= earliest else { continue }
            guard let colon = parts[1].firstIndex(of: ":") else { continue }
            let message = String(parts[1][parts[1].index(after: colon)...])
            guard let title = ActivityText.title(message, limit: ActivityText.maxCommitLength) else { continue }
            let date = Date(timeIntervalSince1970: seconds)
            items.append(ActivityItem(
                id: "local|\(projectPath)|\(words[1])|\(Int(seconds))",
                kind: .commits,
                action: title,
                repo: repo,
                detail: nil,
                date: date,
                url: nil,
                commitMessage: title,
                hasExactTime: true
            ))
        }
        return items
    }

    /// "owner/name" when the project has a GitHub remote, so it reads like the GitHub rows. Otherwise the folder name.
    static func repoName(gitDirectory gitDir: URL, folder: URL) -> String {
        if let url = GitRemote.githubURL(forGitDirectory: gitDir) {
            let parts = url.path.split(separator: "/")
            if parts.count == 2 { return "\(parts[0])/\(parts[1])" }
        }
        return folder.lastPathComponent
    }
}
