import SwiftUI

/// The GitHub part of Settings: the account and token, then how and when the contributions are refreshed.
/// It returns two Form sections, so it is meant to sit directly inside the Settings Form.
///
/// Contributions is two rows: Automatic refresh, and Last updated. The Refresh icon sits in the section header, and is
/// the same spinning icon as the other Refresh buttons.
struct GitHubSettingsSection: View {
    let store: ContributionStore
    let settings: AppSettings

    /// Every press of Refresh adds one full turn, which is what makes the icon spin once.
    @State private var refreshTurns = 0

    var body: some View {
        Section("GitHub account") {
            GitHubTokenSection(store: store)
        }

        Section {
            LabeledContent("Automatic refresh") {
                Picker("Automatic refresh", selection: intervalSelection) {
                    ForEach(AppSettings.refreshOptions, id: \.self) { minutes in
                        Text(AppSettings.intervalLabel(minutes)).tag(minutes)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            // Only worth saying while an automatic refresh is actually due.
            if store.pausedForLowPower && settings.refreshIntervalMinutes > 0 {
                note("Automatic refresh is paused in Low Power Mode. Use the refresh icon to update.", isProblem: false)
            }

            LabeledContent("Last updated") {
                Text(lastUpdatedText)
                    .foregroundStyle(.secondary)
            }

            if let problem = refreshProblem {
                note(problem, isProblem: true)
            }
        } header: {
            HStack {
                Text("Contributions")
                Spacer()
                refreshButton
            }
        }
    }

    // MARK: Pieces

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

    private func note(_ text: String, isProblem: Bool) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isProblem ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
