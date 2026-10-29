import AppKit
import SwiftUI

/// Owns the branch widget panel and decides what it shows.
///
/// Which project: when Xcode or VS Code comes to the front, ask it which project is open and match the answer
/// against the saved projects. Only saved projects are ever shown.
/// Which branch: read from the project's HEAD file, and kept current by watching the Git directory.
/// Nothing here polls, and no timer is involved.
@Observable
final class BranchWidgetController {
    private(set) var isVisible = false
    private(set) var elevationSummary = "Elevation: not tested yet (show the widget first)"
    /// What the last detection found, for the Widget tab.
    private(set) var detectionSummary = "Open a saved project in Xcode or VS Code and Gitzy will find it."
    /// The branch of the project being shown. Nil until a saved project has been detected.
    private(set) var head: GitHead?

    var position: WidgetPosition { settings.widgetPosition }

    private struct Detected {
        let editor: CodeEditor
        let result: Detection
    }

    private let settings: AppSettings
    private let projects: ProjectStore
    private let panel = BranchWidgetPanel()
    private let hostingView = NSHostingView(rootView: BranchWidgetView(branch: "", backdrop: .glass))

    @ObservationIgnored private var hasElevated = false
    /// The editor that most recently came to the front.
    @ObservationIgnored private var lastEditor: CodeEditor?
    @ObservationIgnored private var lastDetected: Detected?
    /// Bumped on every detection so a slow answer cannot overwrite a newer one.
    @ObservationIgnored private var detectionToken = 0
    @ObservationIgnored private var activeProjectPath: String?
    @ObservationIgnored private var watcher: GitHeadWatcher?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(settings: AppSettings, projects: ProjectStore) {
        self.settings = settings
        self.projects = projects
        panel.contentView = hostingView

        if let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            lastEditor = CodeEditor(bundleID: id)
        }
        // When the saved project list changes (added, removed, loaded at launch), match again.
        projects.onProjectsChanged = { [weak self] in self?.matchLastDetection() }
        startObserving()
    }

    // MARK: Showing and placing

    func setVisible(_ visible: Bool) {
        isVisible = visible
        guard visible else {
            panel.orderOut(nil)
            return
        }
        refreshContent()
        panel.orderFrontRegardless()   // shows the panel without activating Gitzy

        if !hasElevated {
            hasElevated = true
            elevationSummary = SkyLightElevator.elevate(panel).summary
        }
        // Gitzy itself is in front while its popover is open, so ask the editor that was in front before it.
        if let editor = lastEditor { detect(using: editor) }
    }

    func setPosition(_ newValue: WidgetPosition) {
        settings.setWidgetPosition(newValue)
        if isVisible { refreshContent() }
    }

    // MARK: Look

    /// A different size changes the panel's size, so it is measured and placed again.
    func setScale(_ value: Double) {
        settings.setWidgetScale(value)
        if isVisible { refreshContent() }
    }

    /// Colours do not change the size, so only the drawing is refreshed. That keeps dragging on a colour wheel cheap.
    func setBackground(_ color: RGBAColor?) {
        settings.setWidgetBackground(color)
        refreshLook()
    }

    func setTextColor(_ color: RGBAColor?) {
        settings.setWidgetTextColor(color)
        refreshLook()
    }

    /// Size and both colours back to default.
    func resetAppearance() {
        settings.resetWidgetAppearance()
        if isVisible { refreshContent() }
    }

    private func refreshLook() {
        if isVisible { hostingView.rootView = makeView() }
    }

    private var widgetText: String { head?.label ?? "No project" }

    private func makeView() -> BranchWidgetView {
        BranchWidgetView(
            branch: widgetText,
            backdrop: .glass,
            scale: CGFloat(settings.widgetScale),
            background: settings.widgetBackground?.color,
            textColor: settings.widgetTextColor?.color
        )
    }

    private func refreshContent() {
        let view = makeView()
        hostingView.rootView = view
        guard let screen = NSScreen.screens.first else { return }   // first screen = the one with the menu bar
        // Measure a fresh view, so the size is right straight after the text changed.
        let size = NSHostingView(rootView: view).fittingSize
        panel.setFrame(WidgetPlacement.frame(for: position, size: size, on: Self.geometry(of: screen)), display: false)
    }

    private static func geometry(of screen: NSScreen) -> ScreenGeometry {
        var notch: ScreenGeometry.Notch?
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            notch = ScreenGeometry.Notch(centerX: (left.maxX + right.minX) / 2, height: screen.safeAreaInsets.top)
        }
        return ScreenGeometry(frame: screen.frame, visibleFrame: screen.visibleFrame, notch: notch)
    }

    // MARK: Events

    private func startObserving() {
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let bundleID = app?.bundleIdentifier
                Task { @MainActor in self?.appBecameFrontmost(bundleID: bundleID) }
            }
        )
        observers.append(
            NotificationCenter.default.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.screenChanged() }
            }
        )
    }

    private func appBecameFrontmost(bundleID: String?) {
        guard let bundleID, let editor = CodeEditor(bundleID: bundleID) else { return }
        lastEditor = editor
        if isVisible { detect(using: editor) }   // nothing is asked while the widget is hidden
    }

    private func screenChanged() {
        if isVisible { refreshContent() }
    }

    // MARK: Detecting the project

    private func detect(using editor: CodeEditor) {
        detectionToken += 1
        let token = detectionToken
        switch editor {
        case .xcode:
            handle(XcodeDetector.activeDocument(), from: editor)
        case .vscode:
            Task {
                let result = await Task.detached { VSCodeDetector.lastActiveFolder() }.value
                guard token == detectionToken else { return }
                handle(result, from: editor)
            }
        }
    }

    private func handle(_ result: Detection, from editor: CodeEditor) {
        lastDetected = Detected(editor: editor, result: result)
        matchLastDetection()
    }

    /// Matches the last answer against the saved projects. Also runs when the saved projects change.
    private func matchLastDetection() {
        let saved = projects.rows.map(\.project.path)
        if let active = activeProjectPath, !saved.contains(active) {
            clearActiveProject()   // the project was removed from Gitzy
        }
        guard let detected = lastDetected else { return }

        switch detected.result {
        case .unavailable(let reason):
            // A failed question keeps whatever was showing.
            detectionSummary = "\(detected.editor.name): \(reason)"
        case .found(let path):
            if let match = ProjectMatcher.match(path: path, in: saved) {
                detectionSummary = "\(detected.editor.name): \(URL(fileURLWithPath: match).lastPathComponent)"
                activate(projectPath: match)
            } else {
                let shown = (path as NSString).abbreviatingWithTildeInPath
                detectionSummary = "\(detected.editor.name): \(shown) is not in your saved projects."
            }
        }
    }

    // MARK: Following the branch

    private func activate(projectPath path: String) {
        if path == activeProjectPath {
            if watcher == nil { loadAndWatch(path) }
            return
        }
        watcher?.stop()
        watcher = nil
        activeProjectPath = path
        loadAndWatch(path)
    }

    /// Reads the branch once, then watches for changes. The file work happens off the main thread.
    private func loadAndWatch(_ path: String) {
        let onChange: @Sendable (GitHead) -> Void = { [weak self] newHead in
            Task { @MainActor in self?.headChanged(newHead, forProjectAt: path) }
        }
        Task {
            let loaded = await Task.detached { () -> (head: GitHead, watcher: GitHeadWatcher?) in
                let folder = URL(fileURLWithPath: path, isDirectory: true)
                guard let gitDirectory = GitRepositoryService.gitDirectory(forRepoAt: folder) else {
                    return (.unknown, nil)
                }
                let watcher = GitHeadWatcher(gitDirectory: gitDirectory, onChange: onChange)
                return (GitRepositoryService.readHead(inGitDirectory: gitDirectory), watcher)
            }.value

            guard path == activeProjectPath else {   // a different project was picked while this was loading
                loaded.watcher?.stop()
                return
            }
            watcher?.stop()
            watcher = loaded.watcher
            head = loaded.head
            if isVisible { refreshContent() }
        }
    }

    private func headChanged(_ newHead: GitHead, forProjectAt path: String) {
        guard path == activeProjectPath, newHead != head else { return }
        head = newHead
        if isVisible { refreshContent() }
    }

    private func clearActiveProject() {
        watcher?.stop()
        watcher = nil
        activeProjectPath = nil
        head = nil
        if isVisible { refreshContent() }
    }
}
