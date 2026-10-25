import AppKit
import SwiftUI

/// The menu bar icon and its popover.
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()

    init(widget: BranchWidgetController) {
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Gitzy")
            button.target = self
            button.action = #selector(togglePopover)
        }

        // The popover size is set once here and never changed afterwards.
        let hosting = NSHostingController(rootView: PopoverRootView(widget: widget))
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}
