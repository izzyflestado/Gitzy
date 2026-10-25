import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var widget: BranchWidgetController?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let widget = BranchWidgetController()
        self.widget = widget
        menuBar = MenuBarController(widget: widget)
    }
}
