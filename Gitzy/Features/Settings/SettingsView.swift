import SwiftUI

/// The content of the Settings window: one scrolling page, one section view per area.
/// Adding an area later is one more line in the Form.
///
/// `widget` and `projects` are not used yet. They are here so the later Settings steps (Projects, Widget, General)
/// need no new wiring in AppDelegate or MenuBarController.
struct SettingsView: View {
    let widget: BranchWidgetController
    let projects: ProjectStore
    let contributions: ContributionStore
    let settings: AppSettings
    let shortcuts: ShortcutController

    var body: some View {
        Form {
            GitHubSettingsSection(store: contributions, settings: settings)
            IDESettingsSection(settings: settings)
            ShortcutsSettingsSection(controller: shortcuts)
            // Coming next: Projects (terminal app, code editor, default sort, forget all), General, Widget, About.
        }
        .formStyle(.grouped)
        .transaction { $0.animation = nil }
    }
}
