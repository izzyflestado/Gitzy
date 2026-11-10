import SwiftUI

/// The content of the Settings window: one scrolling page. It is a Form (GitHub account), then the Contributions and
/// Default IDE boxes, then a second Form (the other sections). Adding an area later is one more line in the second Form.
///
/// Why two Forms: a Form draws one full-width box per section, so two boxes side by side cannot be a Form section. The
/// two Forms do not scroll themselves (`scrollDisabled`) and are as tall as their content, so the page scrolls as one.
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
        ScrollView {
            VStack(spacing: 0) {
                Form {
                    GitHubSettingsSection(store: contributions, settings: settings)
                }
                .settingsFormLook()

                ContributionsIDESection(store: contributions, settings: settings)

                Form {
                    WidgetAppRulesSection(monitor: widget.appVisibility)
                    WindowsSettingsSection(settings: settings)
                    ShortcutsSettingsSection(controller: shortcuts)
                    // Coming next: Projects (terminal app, code editor, default sort, forget all), General, Widget, About.
                }
                .settingsFormLook()
            }
        }
    }
}

private extension View {
    /// A grouped Form that is as tall as its content and does not scroll on its own, so it can sit in the page's scroll.
    func settingsFormLook() -> some View {
        self
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)
            .transaction { $0.animation = nil }
    }
}
