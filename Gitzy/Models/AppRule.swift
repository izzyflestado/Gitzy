import Foundation

/// What Gitzy does with the branch widget while an app is visible.
nonisolated enum AppRule: String, CaseIterable, Identifiable, Sendable {
    /// The widget may show while this app is visible.
    case show
    /// The widget is hidden while this app is visible.
    case hide

    var id: String { rawValue }

    var title: String {
        switch self {
        case .show: return "Show"
        case .hide: return "Hide"
        }
    }
}

/// Which kind of app wins when a Show app and a Hide app are visible at the same time (split screen, tiled windows).
nonisolated enum RulePriority: String, CaseIterable, Identifiable, Sendable {
    case hideWins
    case showWins

    static let standard: RulePriority = .hideWins

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hideWins: return "Hide apps win"
        case .showWins: return "Show apps win"
        }
    }
}

/// The rules as they are saved in UserDefaults: a plain dictionary from bundle identifier to "show" or "hide".
/// Anything that is not a known rule is left out, so a damaged or newer value can never stop the app from starting.
nonisolated enum AppRuleStorage {
    static func decode(_ saved: [String: Any]?) -> [String: AppRule] {
        var rules: [String: AppRule] = [:]
        for (appID, value) in saved ?? [:] {
            guard !appID.isEmpty, let text = value as? String, let rule = AppRule(rawValue: text) else { continue }
            rules[appID] = rule
        }
        return rules
    }

    static func encode(_ rules: [String: AppRule]) -> [String: String] {
        rules.mapValues { $0.rawValue }
    }
}
