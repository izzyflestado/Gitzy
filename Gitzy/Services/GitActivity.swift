import Foundation

/// When a repository last had commit activity, read from the repository's own log file (`logs/HEAD`).
/// Like the rest of GitRepositoryService it never starts a git process and never writes anything.
///
/// The log records what happened to HEAD on this Mac: commits, merges, pulls, rebases, cherry-picks, reverts and clones.
/// Switching branches is not counted. A commit made on another computer only shows up here once it has been pulled.
nonisolated extension GitRepositoryService {

    /// How much of the end of the log is read. The newest entries are at the end, and this holds hundreds of them.
    private static let logWindow: UInt64 = 65_536

    /// The start of the message on a log line that counts as activity ("commit (initial): ...", "pull: Fast-forward").
    private static let activityPrefixes = ["commit", "merge", "pull", "cherry-pick", "revert", "rebase", "clone"]

    /// Nil when the folder is not a repository, has no log, or the log has no activity in its recent part.
    static func lastActivity(ofProjectAt path: String) -> Date? {
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        guard let gitDir = gitDirectory(forRepoAt: folder) else { return nil }
        return lastActivity(inGitDirectory: gitDir)
    }

    static func lastActivity(inGitDirectory gitDir: URL) -> Date? {
        let log = gitDir.appendingPathComponent("logs").appendingPathComponent("HEAD")
        guard let handle = try? FileHandle(forReadingFrom: log) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd() else { return nil }
        let start = size > logWindow ? size - logWindow : 0
        guard (try? handle.seek(toOffset: start)) != nil, let data = try? handle.readToEnd() else { return nil }

        var text = String(decoding: data, as: UTF8.self)
        // Reading from the middle of the file starts part way through a line, so drop that first piece.
        if start > 0, let newline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: newline)...])
        }
        return parseLastActivity(reflog: text)
    }

    /// The time of the newest line that is commit activity.
    /// A line looks like: `<old id> <new id> Name <email> <unix time> <zone>` + tab + `commit: message`.
    static func parseLastActivity(reflog: String) -> Date? {
        for line in reflog.split(whereSeparator: \.isNewline).reversed() {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let message = parts[1]
            guard activityPrefixes.contains(where: { message.hasPrefix($0) }) else { continue }
            // The unix time is the second word from the end, just before the time zone ("+0800").
            let words = parts[0].split(separator: " ")
            guard words.count >= 2, let seconds = TimeInterval(words[words.count - 2]) else { continue }
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }
}
