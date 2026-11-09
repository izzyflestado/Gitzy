import Foundation

/// Whether the widget may show, and the reason in plain words (it is what Settings displays).
nonisolated struct VisibilityDecision: Equatable, Sendable {
    let showWidget: Bool
    let reason: String
}

/// Turns "these apps are visible" into "the widget shows" or "the widget hides".
///
///   - Show and Hide apps both visible: the priority decides.
///   - Only Show apps visible: shown. Only Hide apps visible: hidden.
///   - None of the apps with a rule visible: hidden when at least one Show app is set up (the widget is only
///     wanted while one of them is in view), otherwise shown.
///   - No rules at all: shown.
nonisolated enum VisibilityRules {
    static func decide(
        visible: [String],
        rules: [String: AppRule],
        priority: RulePriority,
        name: (String) -> String = { $0 }
    ) -> VisibilityDecision {
        if rules.isEmpty {
            return VisibilityDecision(showWidget: true, reason: "No apps are set up, so the widget always shows.")
        }

        let showing = visible.filter { rules[$0] == .show }
        let hiding = visible.filter { rules[$0] == .hide }

        switch (showing.isEmpty, hiding.isEmpty) {
        case (false, false):
            let both = "\(list(showing, name)) (Show) and \(list(hiding, name)) (Hide) are both visible."
            switch priority {
            case .hideWins:
                return VisibilityDecision(showWidget: false, reason: both + " Hide apps win.")
            case .showWins:
                return VisibilityDecision(showWidget: true, reason: both + " Show apps win.")
            }
        case (false, true):
            return VisibilityDecision(showWidget: true, reason: "\(list(showing, name)) is visible (Show).")
        case (true, false):
            return VisibilityDecision(showWidget: false, reason: "\(list(hiding, name)) is visible (Hide).")
        case (true, true):
            if rules.values.contains(.show) {
                return VisibilityDecision(showWidget: false, reason: "None of your Show apps is visible.")
            }
            return VisibilityDecision(showWidget: true, reason: "No Hide app is visible.")
        }
    }

    private static func list(_ appIDs: [String], _ name: (String) -> String) -> String {
        appIDs.map(name).joined(separator: ", ")
    }
}
