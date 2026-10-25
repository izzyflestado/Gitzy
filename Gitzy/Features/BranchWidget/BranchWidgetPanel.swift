import AppKit

/// Borderless, transparent panel that never takes focus and never activates Gitzy.
/// Even without SkyLight it sits at a very high level on every Space, including fullscreen ones.
final class BranchWidgetPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        appearance = NSAppearance(named: .darkAqua)
        animationBehavior = .none
        isFloatingPanel = true
        hidesOnDeactivate = false      // panels hide when the app is inactive unless told not to
        ignoresMouseEvents = true      // click-through; the optional buttons (Milestone 6) will change this
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
