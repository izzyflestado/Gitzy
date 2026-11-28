import Foundation

/// Finds the message of a commit for a "Made 1 commit" row on the GitHub list, so that row can read like a local one.
///
/// GitHub's contribution summary only says how many commits a repository got on a day. So this asks each repository for
/// the viewer's own recent commits on its default branch (headlines only, never code or file names), and then matches
/// them to the days: newest commit to the newest day, taking as many as that day's count. If the commits found do not
/// fit the counts, the row keeps "Made 1 commit". A wrong message is worse than none.
nonisolated enum CommitMessages {
    /// Most commits asked for per repository. A page covers about 30 days, so this is plenty.
    private static let perRepository = 100
    /// A commit counts as belonging to a day only when it was made within this long of the day's mark. A day's mark is
    /// the start of that calendar day, and GitHub files a commit under the date in the commit's own time zone.
    private static let tolerance: TimeInterval = 40 * 3_600

    /// What to look for: repositories ("owner/name") that have a single-commit day in these rows.
    static func repositories(in items: [ActivityItem]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { item in
            guard item.kind == .commits, item.commitCount == 1, seen.insert(item.repo).inserted else { return nil }
            return item.repo
        }
    }

    /// The question for GitHub: one aliased lookup per repository (r0, r1...). Names already passed ActivityText.repoName,
    /// and `viewerID` is checked here, so nothing odd can end up inside the query text.
    static func query(viewerID: String, repositories: [String], from: Date, to: Date) -> String? {
        guard isSafeID(viewerID) else { return nil }
        let formatter = ISO8601DateFormatter()
        let since = formatter.string(from: from.addingTimeInterval(-tolerance))
        let until = formatter.string(from: to.addingTimeInterval(tolerance))
        var lookups: [String] = []
        for (index, repo) in repositories.enumerated() {
            let parts = repo.split(separator: "/")
            guard parts.count == 2, ActivityText.repoName(repo) != nil else { continue }
            lookups.append("""
            r\(index): repository(owner: "\(parts[0])", name: "\(parts[1])") { defaultBranchRef { target { ... on Commit { \
            history(first: \(perRepository), since: "\(since)", until: "\(until)", author: {id: "\(viewerID)"}) { \
            nodes { messageHeadline committedDate } } } } } }
            """)
        }
        guard !lookups.isEmpty else { return nil }
        return "query { " + lookups.joined(separator: " ") + " }"
    }

    private static func isSafeID(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 100 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "=") }
    }

    /// One commit found in a repository.
    struct Found: Equatable, Sendable {
        let date: Date
        let headline: String
    }

    /// Reads GitHub's answer to `query`. The result is keyed by "owner/name". A repository that did not answer is left out.
    static func parse(_ data: Data, repositories: [String]) -> [String: [Found]] {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let body = root["data"] as? [String: Any]
        else { return [:] }
        let plain = ISO8601DateFormatter()
        var result: [String: [Found]] = [:]
        for (index, repo) in repositories.enumerated() {
            guard let lookup = body["r\(index)"] as? [String: Any],
                  let branch = lookup["defaultBranchRef"] as? [String: Any],
                  let target = branch["target"] as? [String: Any],
                  let history = target["history"] as? [String: Any],
                  let nodes = history["nodes"] as? [[String: Any]]
            else { continue }
            result[repo] = nodes.compactMap { node in
                guard let text = node["committedDate"] as? String, let date = plain.date(from: text),
                      let headline = ActivityText.title(node["messageHeadline"] as? String, limit: ActivityText.maxCommitLength)
                else { return nil }
                return Found(date: date, headline: headline)
            }
        }
        return result
    }

    /// Gives each single-commit row its message, where the commits found fit the counts. Other rows are returned as they were.
    static func attach(to items: [ActivityItem], found: [String: [Found]]) -> [ActivityItem] {
        var messages: [String: String] = [:]   // item id -> headline
        for (repo, commits) in found {
            let days = items
                .filter { $0.kind == .commits && $0.repo == repo }
                .sorted { $0.date > $1.date }
            guard let newest = days.first else { continue }
            // Commits newer than the newest day cannot belong to any of these days (they belong to a newer page).
            var queue = commits
                .filter { $0.date <= newest.date.addingTimeInterval(tolerance) }
                .sorted { $0.date > $1.date }
            for day in days {
                let count = day.commitCount ?? 0
                guard count > 0, queue.count >= count else { break }
                let taken = Array(queue.prefix(count))
                queue.removeFirst(count)
                // A day whose commits are not near its mark means the matching has drifted. Stop trusting it from here on.
                guard taken.allSatisfy({ abs($0.date.timeIntervalSince(day.date)) <= tolerance }) else { break }
                if count == 1 { messages[day.id] = taken[0].headline }
            }
        }
        return items.map { item in
            guard let message = messages[item.id] else { return item }
            var copy = item
            copy.commitMessage = message
            copy.action = message
            return copy
        }
    }
}
