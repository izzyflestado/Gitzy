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
    /// The graph: the last 12 months, one array per week column, as GitHub returns them.
    let weeks: [[ContributionDay]]
    let totalContributions: Int
    let currentStreak: Int
    let fetchedAt: Date
}
