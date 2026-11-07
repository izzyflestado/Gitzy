import AppKit
import SwiftUI

/// The menu bar icon and its popover.
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let projects: ProjectStore
    private let contributions: ContributionStore
    private let settingsWindow: SettingsWindowController

    init(widget: BranchWidgetController, projects: ProjectStore, contributions: ContributionStore, settings: AppSettings, settingsWindow: SettingsWindowController) {
        self.settingsWindow = settingsWindow
        self.projects = projects
        self.contributions = contributions
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Gitzy")
            button.target = self
            button.action = #selector(togglePopover)
        }

        // The popover size is set once here and never changed afterwards.
        let root = PopoverRootView(
            widget: widget,
            projects: projects,
            contributions: contributions,
            settings: settings,
            openSettings: { [weak self] in self?.openSettings() }
        )
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []   // stop SwiftUI from resizing the popover to its content
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 360, height: 440)
        popover.animates = false
        popover.behavior = .transient
    }

    /// Opens the popover, or closes it when it is open. The menu bar icon and the "Open Gitzy menu" shortcut both call this.
    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // A menu bar app is not the active app. Becoming active lets the token field take keyboard input.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            refreshOnOpen()
        }
    }
    
    /// Every time the popover opens, the data in it is read again, so what you see is fresh.
    /// The GitHub refresh does nothing if one is already running, and waits out a rate limit.
    private func refreshOnOpen() {
        contributions.refresh()
        Task { await projects.refresh() }
    }

    /// The popover goes first, then the Settings window is activated and brought to the front.
    private func openSettings() {
        popover.performClose(nil)
        settingsWindow.show()
    }
}
