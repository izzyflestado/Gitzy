import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Contributions and Default IDE as two separate boxes side by side, about 65% and 35% wide.
/// This is NOT a Form section: a Form puts every section in one full-width box, so two boxes side by side cannot be made
/// inside it. SettingsView puts this view between two Forms (GitHub account above, the other sections below), all in one
/// scrolling page.
///
/// Each box is a title and two rows, so the rows line up across the two:
///
///     Contributions ⟳                      Default IDE
///     Automatic refresh   [ 30 min ]       [        Automatic        ]    (blue while it is in use)
///     Last updated        Today, 9:41      [   icon  Name / Choose…  ]
///
/// Contributions: the refresh icon is the same spinning icon as the other Refresh buttons.
/// Default IDE: Automatic lets the project decide (Xcode for Xcode projects and Swift packages, VS Code for the rest).
/// The second button shows the chosen app's icon and name, and says Choose… when hovered. A chosen app that has since
/// been moved or deleted is ignored, and Automatic is used and shows blue.
struct ContributionsIDESection: View {
    let store: ContributionStore
    let settings: AppSettings

    /// Every press of Refresh adds one full turn, which is what makes the icon spin once.
    @State private var refreshTurns = 0
    @State private var hoveringChoice = false
    @Environment(\.colorScheme) private var colorScheme

    private let rowHeight: CGFloat = 24

    var body: some View {
        WeightedColumns(weights: [65, 35], spacing: 12) {
            contributionsColumn
            ideColumn
        }
        .padding(.horizontal, 20)
    }

    // MARK: Contributions

    private var contributionsColumn: some View {
        box {
            HStack(spacing: 6) {
                title("Contributions")
                refreshButton
                Spacer()
            }
            .frame(height: rowHeight)

            HStack {
                label("Automatic refresh")
                Spacer()
                Picker("Automatic refresh", selection: intervalSelection) {
                    ForEach(AppSettings.refreshOptions, id: \.self) { minutes in
                        Text(AppSettings.intervalLabel(minutes)).tag(minutes)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .frame(height: rowHeight)

            HStack {
                label("Last updated")
                Spacer()
                Text(lastUpdatedText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(height: rowHeight)

            // Only when there is something to say.
            if store.pausedForLowPower && settings.refreshIntervalMinutes > 0 {
                note("Automatic refresh is paused in Low Power Mode. Use the refresh icon to update.", isProblem: false)
            }
            if let problem = refreshProblem {
                note(problem, isProblem: true)
            }
        }
    }

    private var refreshButton: some View {
        Button {
            refreshTurns += 1
            store.refresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(Double(refreshTurns) * 360))
                .animation(.linear(duration: 1), value: refreshTurns)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .disabled(!store.isConnected || store.isLoading)
        .help("Refresh contributions")
        .accessibilityLabel("Refresh contributions")
    }

    /// The picker changes the setting through the store, so the refresh timer is restarted with it.
    private var intervalSelection: Binding<Int> {
        Binding(
            get: { settings.refreshIntervalMinutes },
            set: { store.setRefreshInterval($0) }
        )
    }

    /// Why the last refresh failed. Hidden while a new refresh is running, like on the GitHub tab.
    private var refreshProblem: String? {
        store.isLoading ? nil : store.refreshError
    }

    private var lastUpdatedText: String {
        if store.isLoading { return "Loading…" }
        guard store.isConnected else { return "Not connected" }
        guard let snapshot = store.snapshot else { return "No data yet" }
        let time = snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(snapshot.fetchedAt) {
            return "Today, \(time)"
        }
        let day = snapshot.fetchedAt.formatted(.dateTime.month(.abbreviated).day())
        return "\(day), \(time)"
    }

    // MARK: Default IDE

    private var ideColumn: some View {
        box {
            title("Default IDE")
                .frame(height: rowHeight)

            Button { settings.setIDEApp(nil) } label: {
                Text("Automatic")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(chosenURL == nil ? Color.accentColor : Color.gray)
            .frame(height: rowHeight)

            Button(action: chooseApp) {
                HStack(spacing: 6) {
                    if let url = chosenURL, !hoveringChoice {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(url.deletingPathExtension().lastPathComponent)
                            .lineLimit(1)
                    } else {
                        Text("Choose…")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(chosenURL != nil ? Color.accentColor : Color.gray)
            .onHover { hoveringChoice = $0 }
            .frame(height: rowHeight)
        }
    }

    /// The chosen app, when one is chosen and still installed.
    private var chosenURL: URL? {
        guard let path = settings.ideAppPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose a code editor"
        panel.message = "Pick the app that \"Open in default IDE\" should use."
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.setIDEApp(url)
    }

    // MARK: Pieces

    /// A box of its own, filling the width and height it is given. The fill is meant to look like the boxes in the Form
    /// below: white in light mode, a little lighter than the window in dark mode.
    private func box<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
        )
    }

    /// The name of a box: bigger and stronger than the rows under it.
    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .semibold))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
    }

    private func note(_ text: String, isProblem: Bool) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isProblem ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Puts its children in a row with widths in the given proportions (65 and 35 give 65% and 35%), all the same height.
private struct WeightedColumns: Layout {
    let weights: [CGFloat]
    let spacing: CGFloat

    private func widths(for total: CGFloat, count: Int) -> [CGFloat] {
        let usable = max(0, total - spacing * CGFloat(max(0, count - 1)))
        let sum = weights.prefix(count).reduce(0, +)
        guard sum > 0 else { return Array(repeating: usable / CGFloat(max(1, count)), count: count) }
        return (0..<count).map { usable * (weights.indices.contains($0) ? weights[$0] : 0) / sum }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 500
        let columnWidths = widths(for: total, count: subviews.count)
        var height: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidths[index], height: nil))
            height = max(height, size.height)
        }
        return CGSize(width: total, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidths = widths(for: bounds.width, count: subviews.count)
        var x = bounds.minX
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: columnWidths[index], height: bounds.height)
            )
            x += columnWidths[index] + spacing
        }
    }
}
