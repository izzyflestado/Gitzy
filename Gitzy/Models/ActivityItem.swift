import Foundation

/// What kind of thing a row in "Recent activity" is. The view picks an icon from it.
nonisolated enum ActivityKind: Sendable {
    case commits
    case pullRequest
    case issue
    case review
    case repository
}

/// One row of "Recent activity", in the style of GitHub's own contribution summary:
/// "Made 3 commits", "Opened pull request", "Reviewed pull request", "Opened issue", "Created repository".
/// It holds no commit messages and no code, only the kind of thing, where it happened, and when.
nonisolated struct ActivityItem: Equatable, Identifiable, Sendable {
    let id: String
    let kind: ActivityKind
    /// The first line, for example "Made 3 commits".
    let action: String
    /// "owner/name" of the repository. Already checked by ActivityParser.
    let repo: String
    /// "#12 Fix the crash" for a pull request or an issue. Nil for commits and new repositories.
    let detail: String?
    let date: Date
    /// Where a click goes. Already checked by GitHubLink, so it is always an https address on github.com.
    let url: URL?

    /// The second line: the repository, then the detail when there is one.
    var subtitle: String {
        guard let detail else { return repo }
        return "\(repo) · \(detail)"
    }
}

/// What one load of the list brings back.
nonisolated struct ActivityPage: Equatable, Sendable {
    /// Newest first.
    let items: [ActivityItem]
    /// The list now reaches back to this moment. The next "Load more" asks for what is just before it.
    let nextEnd: Date
}

/// Which stretch of time to ask GitHub about. Each request covers 30 days, and the list never reaches back more than a year.
nonisolated enum ActivityWindows {
    static let days = 30
    static let maxDaysBack = 365

    /// The window that ends at `end` and starts 30 days earlier, but never earlier than `limit`.
    /// Nil when `end` has already reached `limit`, which means there is nothing older to ask for.
    static func window(endingAt end: Date, notBefore limit: Date) -> (from: Date, to: Date)? {
        guard end > limit else { return nil }
        let from = max(end.addingTimeInterval(-Double(days) * 86_400), limit)
        return (from, end)
    }
}

/// Puts loaded pages together. A row is kept once, and the list is always newest first.
nonisolated enum ActivityMerge {
    /// Adds `more` to `existing`. A row that is in both is kept once.
    static func appending(_ more: [ActivityItem], to existing: [ActivityItem]) -> [ActivityItem] {
        var seen = Set<String>()
        var unique: [ActivityItem] = []
        for item in existing + more where seen.insert(item.id).inserted {
            unique.append(item)
        }
        return unique.sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
    }

    /// A refresh reads the newest stretch again. Whatever it covers is replaced by what it found (so a pull request
    /// that was deleted disappears), and rows from further back, loaded earlier with "Load more", are kept.
    /// `coveredBack` is where the refresh stopped reading.
    static func refreshing(_ existing: [ActivityItem], with fresh: [ActivityItem], coveredBack: Date) -> [ActivityItem] {
        appending(existing.filter { $0.date <= coveredBack }, to: fresh)
    }
}

/// How a row's date reads: "Today", "Yesterday", "3 days ago", "2 weeks ago", then "Oct 12" (with the year when it is not this one).
nonisolated enum ActivityDateLabel {
    static func text(for date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: date),
            to: calendar.startOfDay(for: now)
        ).day ?? 0

        switch days {
        case ..<1:
            return "Today"
        case 1:
            return "Yesterday"
        case 2..<7:
            return "\(days) days ago"
        case 7..<30:
            let weeks = days / 7
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            // Built from the same calendar and time zone that counted the days, so the day shown is the day counted.
            let style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            return sameYear
                ? date.formatted(style.month(.abbreviated).day())
                : date.formatted(style.month(.abbreviated).day().year())
        }
    }
}
