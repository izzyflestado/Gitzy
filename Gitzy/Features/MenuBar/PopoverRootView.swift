import SwiftUI

/// The popover: the name, the three tabs (centred), the chosen tab, and a footer that always sits at the bottom.
/// The GitHub tab is still a temporary test layout. The Settings button closes the popover and opens the Settings window.
///
/// Animations are switched off section by section rather than once at the top, because the two spinning icons
/// (Refresh in the Projects tab, Reset in the Widget tab) are the only animations the app allows itself.
struct PopoverRootView: View {
    let widget: BranchWidgetController
    let projects: ProjectStore
    let contributions: ContributionStore
    let settings: AppSettings
    /// Closes the popover and opens the Settings window.
    let openSettings: () -> Void

    private enum Tab: Hashable {
        case projects, widget, github
    }

    @State private var tab: Tab = .projects

    var body: some View {
        VStack(spacing: 10) {
            Text("Gitzy").font(.headline)

            Picker("Tab", selection: $tab) {
                Text("Projects").tag(Tab.projects)
                Text("Widget").tag(Tab.widget)
                Text("GitHub").tag(Tab.github)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 270)
            .transaction { $0.animation = nil }

            Group {
                switch tab {
                case .projects:
                    ProjectsTestView(store: projects)
                case .widget:
                    WidgetTabView(widget: widget, settings: settings)
                case .github:
                    githubTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
        }
        .padding(16)
        .frame(width: 360, height: 440, alignment: .top)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Divider()
            HStack {
                Button(action: openSettings) {
                    Label("Settings", systemImage: "gearshape")
                }

                Spacer()

                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .transaction { $0.animation = nil }
    }

    // MARK: Tabs

    /// Scrolls only when it does not fit, so the footer never pushes anything out of view.
    ///
    /// The token lives in the Settings window. When there is no token, or GitHub has refused it, the tab itself
    /// points there through `openSettings`.
    /// No "no animation" rule is put on the whole tab, because the refresh icon in it spins; the tab itself applies
    /// that rule to everything else.
    private var githubTab: some View {
        ScrollView {
            ContributionsTestView(store: contributions, openSettings: openSettings)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}
