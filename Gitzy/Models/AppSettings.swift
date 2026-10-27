import AppKit

/// User settings stored in UserDefaults. The GitHub token is NOT here; it lives only in the Keychain.
@Observable
final class AppSettings {
    private static let terminalKey = "terminalAppPath"
    private static let refreshKey = "refreshIntervalMinutes"
    private static let builtInTerminalID = "com.apple.Terminal"

    /// Minutes between automatic GitHub refreshes. 0 means manual only.
    static let refreshOptions = [15, 30, 60, 0]

    static func intervalLabel(_ minutes: Int) -> String {
        minutes == 0 ? "Manual only" : "\(minutes) min"
    }

    private(set) var terminalAppPath: String?
    private(set) var refreshIntervalMinutes = 30

    init() {
        terminalAppPath = UserDefaults.standard.string(forKey: Self.terminalKey)
        if let saved = UserDefaults.standard.object(forKey: Self.refreshKey) as? Int,
           Self.refreshOptions.contains(saved) {
            refreshIntervalMinutes = saved
        }
    }

    func setRefreshInterval(_ minutes: Int) {
        guard Self.refreshOptions.contains(minutes) else { return }
        refreshIntervalMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: Self.refreshKey)
    }

    /// Pass nil to go back to Apple's Terminal.
    func setTerminalApp(_ url: URL?) {
        terminalAppPath = url?.path
        UserDefaults.standard.set(url?.path, forKey: Self.terminalKey)
    }

    /// The chosen terminal, or Apple's Terminal when none is chosen or the chosen app no longer exists.
    var terminalAppURL: URL? {
        if let path = terminalAppPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.builtInTerminalID)
    }

    var terminalName: String {
        terminalAppURL?.deletingPathExtension().lastPathComponent ?? "none found"
    }
}
