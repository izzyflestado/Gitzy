import AppKit

/// User settings stored in UserDefaults. Milestone 3 only needs the terminal app;
/// the rest of the Settings options arrive in later milestones.
@Observable
final class AppSettings {
    private static let terminalKey = "terminalAppPath"
    private static let builtInTerminalID = "com.apple.Terminal"

    private(set) var terminalAppPath: String?

    init() {
        terminalAppPath = UserDefaults.standard.string(forKey: Self.terminalKey)
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
