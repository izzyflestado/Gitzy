import Foundation

/// What this Mac's own git logs say about today: commits made in the saved projects that have a GitHub remote.
nonisolated struct LocalToday: Equatable, Sendable {
    let commits: Int
    /// How many projects those commits are in.
    let projects: Int

    static let none = LocalToday(commits: 0, projects: 0)
}

/// The three states of the dot on the profile picture.
nonisolated enum TodayLevel: Sendable {
    /// Grey: nothing today, neither on GitHub nor on this Mac.
    case quiet
    /// Orange: commits were made on this Mac today, but today's square on the graph is still empty (not pushed yet, say).
    case notOnGitHubYet
    /// Green: today's square on the graph already has contributions.
    case onGitHub
}

/// Today, from two sides: what GitHub's graph shows and what this Mac's git logs show.
nonisolated struct TodayActivity: Equatable, Sendable {
    /// Contributions in today's square of the graph, of every kind (commits, pull requests, issues, reviews).
    let graphCount: Int
    let local: LocalToday

    /// Green as soon as the graph has anything for today. Otherwise orange when there are commits on this Mac,
    /// and grey when there is nothing at all.
    var level: TodayLevel {
        if graphCount > 0 { return .onGitHub }
        return local.commits > 0 ? .notOnGitHubYet : .quiet
    }

    // MARK: Words for the hover card

    var headline: String {
        switch level {
        case .quiet: return "No contributions today."
        case .notOnGitHubYet: return "Committed on this Mac, but not on your graph yet. Maybe it is not pushed?"
        case .onGitHub: return "Already on your GitHub graph."
        }
    }

    var graphText: String {
        switch graphCount {
        case 0: return "No contributions"
        case 1: return "1 contribution"
        default: return "\(graphCount) contributions"
        }
    }

    var localText: String {
        guard local.commits > 0 else { return "No commits" }
        let commits = local.commits == 1 ? "1 commit" : "\(local.commits) commits"
        let projects = local.projects == 1 ? "1 project" : "\(local.projects) projects"
        return "\(commits) in \(projects)"
    }

    // MARK: Working it out

    /// Nil until the graph has loaded, because then nobody knows yet.
    static func make(weeks: [[ContributionDay]]?, local: LocalToday, now: Date = Date(), calendar: Calendar = .current) -> TodayActivity? {
        guard let weeks else { return nil }
        let count = graphCount(in: weeks, on: dayString(for: now, calendar: calendar))
        return TodayActivity(graphCount: count, local: local)
    }

    /// The count in the graph's square for `day` ("2026-11-11"), or 0 when the graph has no such day.
    static func graphCount(in weeks: [[ContributionDay]], on day: String) -> Int {
        // Today is at the end of the graph, so look from the back.
        for week in weeks.reversed() {
            for entry in week where entry.date == day {
                return entry.count
            }
        }
        return 0
    }

    /// The date the way GitHub writes the days of the graph, in the calendar's own time zone.
    static func dayString(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
