import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings?
    private var projects: ProjectStore?
    private var contributions: ContributionStore?
    private var widget: BranchWidgetController?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)

        let settings = AppSettings()
        let projects = ProjectStore(settings: settings)
        let contributions = ContributionStore(settings: settings)
        let widget = BranchWidgetController(settings: settings, projects: projects)
        self.settings = settings
        self.projects = projects
        self.contributions = contributions
        self.widget = widget
        let settingsWindow = SettingsWindowController(widget: widget, projects: projects, contributions: contributions, settings: settings)
        self.settingsWindow = settingsWindow
        menuBar = MenuBarController(widget: widget, projects: projects, contributions: contributions, settings: settings, settingsWindow: settingsWindow)
    }

    /// Closing the Settings window must never quit the app. Gitzy lives in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
