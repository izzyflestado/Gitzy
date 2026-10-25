import AppKit
import SwiftUI

/// Owns the branch widget panel.
/// Milestone 2 shows a fixed test label so glass and elevation can be checked.
/// Real branch detection (Milestone 6) replaces the test label.
@Observable
final class BranchWidgetController {
    private(set) var isVisible = false
    private(set) var backdrop: WidgetBackdrop = .glass
    private(set) var elevationSummary = "Elevation: not tested yet (show the widget first)"

    private static let testLabel = "branch-widget-test"

    private let panel = BranchWidgetPanel()
    private let hostingView = NSHostingView(
        rootView: BranchWidgetView(branch: BranchWidgetController.testLabel, backdrop: .glass)
    )
    @ObservationIgnored private var hasElevated = false

    init() {
        panel.contentView = hostingView
    }

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
    }

    func setBackdrop(_ newValue: WidgetBackdrop) {
        backdrop = newValue
        if isVisible { refreshContent() }
    }

    private func refreshContent() {
        hostingView.rootView = BranchWidgetView(branch: Self.testLabel, backdrop: backdrop)
        guard let screen = NSScreen.screens.first else { return }   // first screen = the one with the menu bar
        panel.setFrame(Self.frame(for: hostingView.fittingSize, on: screen), display: false)
    }

    /// Temporary placement. Notched display: centered just under the camera housing.
    /// Any other display: top-right corner below the menu bar. Milestone 6 adds all five positions.
    private static func frame(for size: NSSize, on screen: NSScreen) -> NSRect {
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            let gap: CGFloat = 4
            let centerX = (left.maxX + right.minX) / 2
            return NSRect(
                x: centerX - size.width / 2,
                y: screen.frame.maxY - screen.safeAreaInsets.top - gap - size.height,
                width: size.width,
                height: size.height
            )
        }

        let inset: CGFloat = 8
        let area = screen.visibleFrame
        return NSRect(
            x: area.maxX - size.width - inset,
            y: area.maxY - size.height - inset,
            width: size.width,
            height: size.height
        )
    }
}
