import AppKit
import SwiftUI

/// Owns the Settings window.
///
/// Gitzy is a menu bar app, so it is not the active app until something activates it. `show()` therefore activates
/// Gitzy first, otherwise the window would open behind whatever app is in front. The caller closes the popover
/// before calling it.
///
/// The window is built the first time it is asked for and let go of when it is closed. That keeps nothing in memory
/// while Settings is shut, and it means a half-typed token can never linger in a hidden window.
/// Choosing Settings while the window is already open just brings that same window to the front.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let widget: BranchWidgetController
    private let projects: ProjectStore
    private let contributions: ContributionStore
    private let settings: AppSettings

    private var window: NSWindow?

    init(widget: BranchWidgetController, projects: ProjectStore, contributions: ContributionStore, settings: AppSettings) {
        self.widget = widget
        self.projects = projects
        self.contributions = contributions
        self.settings = settings
        super.init()
    }

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: Private

    private func makeWindow() -> NSWindow {
        let root = SettingsView(widget: widget, projects: projects, contributions: contributions, settings: settings)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []   // the window keeps the size set below; SwiftUI does not resize it

        let window = NSWindow(contentViewController: hosting)
        window.title = "Gitzy Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 520, height: 560))
        window.contentMinSize = NSSize(width: 480, height: 360)
        window.center()
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Not released right here, because AppKit is still in the middle of closing the window.
        // If Settings was opened again in the meantime, the window is visible and is kept.
        Task { [weak self] in
            guard let self, self.window?.isVisible != true else { return }
            self.window = nil
        }
    }
}
