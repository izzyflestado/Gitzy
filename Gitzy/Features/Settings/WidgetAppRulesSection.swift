import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// App-Based Widget Visibility: choose apps that show or hide the branch widget while they are visible.
///
/// An app counts as visible when enough of its window is showing: not hidden behind other windows, not minimized,
/// not hidden with Cmd-H, and on the current Space.
/// The widget's own Show Widget switch still has the last word: these rules can only hide a widget that is switched on.
///
/// The heading is above the box, like the other sections. Rows: the Enabled switch (a tick), the threshold and its percentage, a full-width slider, what wins in a conflict, and the
/// list of apps (folds away; the plus adds an app by picking it from Applications).
struct WidgetAppRulesSection: View {
    let monitor: AppVisibilityMonitor

    @State private var appsExpanded = true

    var body: some View {
        Section {
            LabeledContent("Enabled") {
                Toggle("Enabled", isOn: Binding(
                    get: { monitor.isEnabled },
                    set: { monitor.setEnabled($0) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }

            if monitor.isEnabled {
                LabeledContent("Visibility Threshold") {
                    Text("\(Int((monitor.threshold * 100).rounded()))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                thresholdSlider

                Picker("Conflicting App Rules", selection: Binding(
                    get: { monitor.priority },
                    set: { monitor.setPriority($0) }
                )) {
                    ForEach(RulePriority.allCases) { priority in
                        Text(priority.title).tag(priority)
                    }
                }

                // The Apps line: the name, then + (add an app) and the open/close arrow on the right.
                HStack(spacing: 8) {
                    Text("Apps")
                    Spacer()
                    Button(action: chooseApp) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help("Add an app")
                    .accessibilityLabel("Add an app")

                    Button {
                        appsExpanded.toggle()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(appsExpanded ? 90 : 0))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(appsExpanded ? "Hide the apps" : "Show the apps")
                    .accessibilityLabel(appsExpanded ? "Hide the apps" : "Show the apps")
                }

                if appsExpanded {
                    if monitor.rules.isEmpty {
                        Text("No apps yet")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sortedAppIDs, id: \.self) { appID in
                        ruleRow(appID)
                    }
                }
            }
        } header: {
            Text("App-Based Widget Visibility")
        }
    }

    // MARK: How much must show

    /// Full width. It has no `step`, because a step makes macOS draw tick marks under it. Values are whole percents.
    private var thresholdSlider: some View {
        Slider(
            value: Binding(
                get: { monitor.threshold },
                set: { value in
                    let whole = (value * 100).rounded() / 100
                    if whole != monitor.threshold { monitor.setThreshold(whole) }
                }
            ),
            in: AppVisibilityMonitor.thresholdRange
        )
        .labelsHidden()
        .accessibilityLabel("Visibility threshold")
    }

    // MARK: The apps

    private var sortedAppIDs: [String] {
        monitor.rules.keys.sorted {
            AppIdentity.name(for: $0).localizedCaseInsensitiveCompare(AppIdentity.name(for: $1)) == .orderedAscending
        }
    }

    private func ruleRow(_ appID: String) -> some View {
        let name = AppIdentity.name(for: appID)
        return HStack(spacing: 10) {
            Image(nsImage: AppIdentity.icon(for: appID))
                .resizable()
                .frame(width: 20, height: 20)
            Text(name)
                .lineLimit(1)
                .foregroundStyle(AppIdentity.isInstalled(appID) ? Color.primary : Color.secondary)
            Spacer()
            Picker("Rule for \(name)", selection: Binding(
                get: { monitor.rules[appID] ?? .show },
                set: { monitor.setRule($0, for: appID) }
            )) {
                ForEach(AppRule.allCases) { rule in
                    Text(rule.title).tag(rule)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 110)
            Button {
                monitor.removeRule(for: appID)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove \(name)")
            .accessibilityLabel("Remove \(name)")
        }
    }

    /// Opens the Applications folder to pick from. The app is added as a Show app; change it in its row.
    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.message = "Pick the app that should show or hide the branch widget."
        panel.prompt = "Add"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        monitor.setRule(.show, for: id)
    }
}
