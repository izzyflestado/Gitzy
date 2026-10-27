import AppKit
import SwiftUI

/// The menu bar icon and its popover.
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(widget: BranchWidgetController, projects: ProjectStore, contributions: ContributionStore, settings: AppSettings) {
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Gitzy")
            button.target = self
            button.action = #selector(togglePopover)
        }

        // The popover size is set once here and never changed afterwards.
        let root = PopoverRootView(widget: widget, projects: projects, contributions: contributions, settings: settings)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = []   // stop SwiftUI from resizing the popover to its content
        popover.contentViewController = hosting
        popover.contentSize = NSSize(width: 360, height: 440)
        popover.animates = false
        popover.behavior = .transient
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // A menu bar app is not the active app. Becoming active lets the token field take keyboard input.
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
