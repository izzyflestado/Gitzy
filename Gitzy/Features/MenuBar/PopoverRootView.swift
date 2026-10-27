import SwiftUI

/// Milestone 4 placeholder with three test tabs. The real Contributions and Projects tabs, the footer
/// and the Settings window arrive in Milestone 5. The Widget tab is the temporary home of the widget controls.
struct PopoverRootView: View {
    let widget: BranchWidgetController
    let projects: ProjectStore
    let contributions: ContributionStore
    let settings: AppSettings

    private enum Tab: Hashable {
        case github, projects, widget
    }

    @State private var tab: Tab = .github

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gitzy").font(.headline)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }

            Picker("Tab", selection: $tab) {
                Text("GitHub").tag(Tab.github)
                Text("Projects").tag(Tab.projects)
                Text("Widget").tag(Tab.widget)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch tab {
                case .github:
                    githubTab
                case .projects:
                    ProjectsTestView(store: projects, settings: settings)
                case .widget:
                    widgetTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(width: 360, height: 440, alignment: .topLeading)
        .transaction { $0.animation = nil }
    }

    private var githubTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            ContributionsTestView(store: contributions, settings: settings)
            Divider()
            GitHubTokenSection(store: contributions)
        }
    }

    private var widgetTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show branch widget", isOn: Binding(
                get: { widget.isVisible },
                set: { widget.setVisible($0) }
            ))
            .toggleStyle(.checkbox)

            HStack {
                Text("Position")
                Spacer()
                Picker("Position", selection: Binding(
                    get: { settings.widgetPosition },
                    set: { widget.setPosition($0) }
                )) {
                    ForEach(WidgetPosition.allCases) { position in
                        Text(position.label).tag(position)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            // Fixed height, so a longer message never moves anything.
            VStack(alignment: .leading, spacing: 4) {
                Text(widget.detectionSummary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                Text(widget.elevationSummary)
                    .lineLimit(2)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 64, alignment: .topLeading)
        }
    }
}
