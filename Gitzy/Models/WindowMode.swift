import Foundation

/// What "Open in Finder" and "Open in Terminal" do. The choice is made in Settings, once for Finder and once for
/// Terminal, and applies to the buttons in the project list and to the keyboard shortcuts alike.
nonisolated enum WindowMode: String, CaseIterable, Identifiable, Sendable {
    /// Always open a new window.
    case newWindow
    /// If a window is already showing the project, bring it to the front. Otherwise open a new window.
    /// Gitzy never changes what an existing window is showing, and never types into one.
    case existingWindow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newWindow: return "Always open a new window"
        case .existingWindow: return "Show the existing window"
        }
    }

    // MARK: Remembered choice

    static let finderKey = "finderWindowMode"
    static let terminalKey = "terminalWindowMode"

    /// The saved choice for `key`. Nothing saved, or something unreadable, gives a new window (how it always was).
    static func saved(forKey key: String, in defaults: UserDefaults = .standard) -> WindowMode {
        defaults.string(forKey: key).flatMap(WindowMode.init(rawValue:)) ?? .newWindow
    }
}
