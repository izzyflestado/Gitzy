import Foundation

/// GitHub's five shades. GitHub names them NONE and FIRST_QUARTILE ... FOURTH_QUARTILE.
nonisolated enum ContributionLevel: Int, Sendable {
    case none = 0, first, second, third, fourth

    init(githubName: String) {
        switch githubName {
        case "FIRST_QUARTILE": self = .first
        case "SECOND_QUARTILE": self = .second
        case "THIRD_QUARTILE": self = .third
        case "FOURTH_QUARTILE": self = .fourth
        default: self = .none
        }
    }
}

nonisolated struct ContributionDay: Equatable, Sendable {
    /// "2026-10-26", exactly as GitHub returns it. Never converted to a time zone.
    let date: String
    let count: Int
    let level: ContributionLevel
    /// 0 = Sunday ... 6 = Saturday, as GitHub returns it.
    let weekday: Int
}

/// The last successful answer from GitHub. Nothing else about contributions is kept.
nonisolated struct ContributionSnapshot: Equatable, Sendable {
    let login: String
    /// The display name from the GitHub profile. Nil when the person has not set one.
    let name: String?
    /// Where the profile picture lives. Already checked by AvatarSource, so it is always an avatars.githubusercontent.com address.
    let avatarURL: URL?
    /// The graph: the last 12 months, one array per week column, as GitHub returns them.
    let weeks: [[ContributionDay]]
    let totalContributions: Int
    let currentStreak: Int
    let fetchedAt: Date

    /// The year of the newest day in the graph, read straight from GitHub's date text ("2026-10-26" is 2026).
    /// Never converted through a time zone.
    var currentYear: Int? {
        guard let newest = weeks.last?.last else { return nil }
        return Int(newest.date.prefix(4))
    }

    /// Contributions from January 1 of `currentYear` up to the newest day in the graph.
    /// The graph covers the last 12 months, so the whole of the current year is always inside it.
    var contributionsThisYear: Int {
        guard let year = currentYear else { return 0 }
        let prefix = String(format: "%04d-", year)
        return weeks.joined().filter { $0.date.hasPrefix(prefix) }.reduce(0) { $0 + $1.count }
    }
}
