import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settings: AppSettings?
    private var projects: ProjectStore?
    private var contributions: ContributionStore?
    private var widget: BranchWidgetController?
    private var menuBar: MenuBarController?
    private var settingsWindow: SettingsWindowController?
    private var shortcuts: ShortcutController?

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
        let shortcuts = ShortcutController(projects: projects)
        self.shortcuts = shortcuts
        let settingsWindow = SettingsWindowController(widget: widget, projects: projects, contributions: contributions, settings: settings, shortcuts: shortcuts)
        self.settingsWindow = settingsWindow
        menuBar = MenuBarController(widget: widget, projects: projects, contributions: contributions, settings: settings, settingsWindow: settingsWindow)
        // The "Open Gitzy menu" shortcut opens the same window as clicking the menu bar icon.
        self.shortcuts?.openMenu = { [weak self] in self?.menuBar?.togglePopover() }
    }

    /// Closing the Settings window must never quit the app. Gitzy lives in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
