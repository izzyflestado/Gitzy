import SwiftUI

/// The popover: the name, the three tabs (centred), the chosen tab, and a footer that always sits at the bottom.
/// The Widget and GitHub tabs are still temporary test layouts, and the Settings window does not exist yet.
///
/// Animations are switched off section by section rather than once at the top, because the spinning refresh icon
/// in the Projects tab is the one animation the app allows itself.
struct PopoverRootView: View {
    let widget: BranchWidgetController
    let projects: ProjectStore
    let contributions: ContributionStore
    let settings: AppSettings

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
                    widgetTab
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
                Button(action: {}) {
                    Label("Settings", systemImage: "gearshape")
                }
                .disabled(true)   // the Settings window is built in a later step
                .help("The Settings window comes in a later step")

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
    private var githubTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ContributionsTestView(store: contributions, settings: settings)
                Divider()
                GitHubTokenSection(store: contributions)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .transaction { $0.animation = nil }
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
        .transaction { $0.animation = nil }
    }
}
