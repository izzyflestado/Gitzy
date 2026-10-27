import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings?
    private var projects: ProjectStore?
    private var widget: BranchWidgetController?
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let settings = AppSettings()
        let projects = ProjectStore(settings: settings)
        let widget = BranchWidgetController()
        self.settings = settings
        self.projects = projects
        self.widget = widget
        menuBar = MenuBarController(widget: widget, projects: projects, settings: settings)
    }
}
