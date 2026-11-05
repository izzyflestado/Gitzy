import AppKit
import Observation

/// The global keyboard shortcuts: which keys do what, registering them with the system, and carrying them out.
///
/// Which repository: the same question the branch widget asks. The editor in front (Xcode or VS Code) is asked
/// which project it has open, and the answer is matched against the saved projects. When Gitzy or another app is in
/// front, the editor that was in front last is asked. If the editor cannot be asked, the last repository found is used.
/// A project that is not saved in Gitzy is never opened.
///
/// The shortcuts are kept in `shortcuts` and saved as they are changed, so the Settings window can edit them
/// later with `setShortcut`. They start as ⌥⇧[ ⌥⇧] ⌥⇧\ .
@Observable
final class ShortcutController {
    /// Whether the shortcuts are switched on. Remembered between launches.
    private(set) var isEnabled = true
    private(set) var shortcuts: [ShortcutAction: KeyShortcut] = ShortcutBindings.defaults
    /// Shortcuts the system would not register (the keys already belong to another app), with the reason.
    private(set) var problems: [ShortcutAction: String] = [:]

    private let projects: ProjectStore
    private let hotKeys = GlobalHotKeys.shared

    /// The editor that most recently came to the front.
    @ObservationIgnored private var lastEditor: CodeEditor?
    /// The saved project the last successful question found.
    @ObservationIgnored private var lastProjectPath: String?
    @ObservationIgnored private var observer: NSObjectProtocol?

    private static let enabledKey = "shortcutsEnabled"
    private static let bindingsKey = "shortcutBindings"

    init(projects: ProjectStore) {
        self.projects = projects
        if let saved = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool {
            isEnabled = saved
        }
        shortcuts = ShortcutBindings.decode(UserDefaults.standard.data(forKey: Self.bindingsKey))

        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            lastEditor = CodeEditor(bundleID: id)
        }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            guard let self else { return }
            Task { @MainActor in self.appBecameFrontmost(bundleID: bundleID) }
        }

        registerAll()
    }

    // MARK: Changing the settings

    func shortcut(for action: ShortcutAction) -> KeyShortcut {
        shortcuts[action] ?? action.defaultShortcut
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        registerAll()
    }

    /// Gives one action new keys. Keys without ⌘, ⌥ or ⌃ are refused.
    func setShortcut(_ shortcut: KeyShortcut, for action: ShortcutAction) {
        guard shortcut.isAllowed else { return }
        shortcuts[action] = shortcut
        saveShortcuts()
        registerAll()
    }

    func resetShortcuts() {
        shortcuts = ShortcutBindings.defaults
        saveShortcuts()
        registerAll()
    }

    // MARK: Registering

    /// Starts again from nothing, so the system always holds exactly what the settings say.
    private func registerAll() {
        hotKeys.unregisterAll()
        problems = [:]
        guard isEnabled else { return }

        for action in ShortcutAction.allCases {
            let result = hotKeys.register(shortcut(for: action)) { [weak self] in
                self?.perform(action)
            }
            switch result {
            case .registered:
                break
            case .alreadyTaken:
                problems[action] = "These keys are already used by another app or by macOS."
            case .failed(let code):
                problems[action] = "macOS would not register these keys (error \(code))."
            }
        }
    }

    private func saveShortcuts() {
        UserDefaults.standard.set(ShortcutBindings.encode(shortcuts), forKey: Self.bindingsKey)
    }

    // MARK: Carrying out

    private func perform(_ action: ShortcutAction) {
        Task {
            // Nothing to open (no editor in front, or a project that is not saved): a beep, because Gitzy has no window to say it in.
            guard let path = await activeProjectPath() else {
                NSSound.beep()
                return
            }
            let project = GitProject(path: path)
            switch action {
            case .openInFinder: projects.openInFinder(project)
            case .openInTerminal: projects.openInTerminal(project)
            case .openInIDE: projects.openInIDE(project)
            }
        }
    }

    // MARK: Which repository

    private func appBecameFrontmost(bundleID: String?) {
        guard let bundleID, let editor = CodeEditor(bundleID: bundleID) else { return }
        lastEditor = editor
    }

    /// The editor in front right now, or the one that was in front last.
    private func editorToAsk() -> CodeEditor? {
        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, let editor = CodeEditor(bundleID: id) {
            return editor
        }
        return lastEditor
    }

    /// The saved project the editor has open, asked right now, so this works whether or not the widget is showing.
    private func activeProjectPath() async -> String? {
        // A project whose folder has gone is not worth opening.
        let saved = projects.rows.filter { !$0.status.isMissing }.map(\.project.path)

        guard let editor = editorToAsk() else { return remembered(in: saved) }

        let detection: Detection
        switch editor {
        case .xcode:
            detection = XcodeDetector.activeDocument()
        case .vscode:
            detection = await Task.detached { VSCodeDetector.lastActiveFolder() }.value
        }

        switch detection {
        case .found(let path):
            // The editor answered. If it is a project Gitzy does not have, the answer is "none", not the last one.
            guard let match = ProjectMatcher.match(path: path, in: saved) else { return nil }
            lastProjectPath = match
            return match
        case .unavailable:
            return remembered(in: saved)
        }
    }

    private func remembered(in saved: [String]) -> String? {
        guard let path = lastProjectPath, saved.contains(path) else { return nil }
        return path
    }
}
