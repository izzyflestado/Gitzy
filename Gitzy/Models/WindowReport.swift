import Foundation

/// A one-line note on what happened the last time Finder or Terminal was asked to show a folder, kept so Settings can
/// show it under the choice. When "Show the existing window" opens a new window anyway, the note says why
/// (no window was showing the folder, macOS did not allow it, the app could not be read) without needing a console.
nonisolated enum WindowReport {
    static let finderKey = "finderWindowReport"
    static let terminalKey = "terminalWindowReport"

    /// Saves `text` with the time, and also writes it to the Xcode console.
    static func record(_ text: String, forKey key: String, at date: Date = Date(), in defaults: UserDefaults = .standard) {
        let time = date.formatted(date: .omitted, time: .standard)
        let line = "\(time) — \(text)"
        defaults.set(line, forKey: key)
        NSLog("Gitzy windows: %@", line)
    }
}
