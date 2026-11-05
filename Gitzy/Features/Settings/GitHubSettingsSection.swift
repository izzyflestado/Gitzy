import SwiftUI

/// The GitHub part of Settings: the account and token, then how and when the contributions are refreshed.
/// It returns two Form sections, so it is meant to sit directly inside the Settings Form.
struct GitHubSettingsSection: View {
    let store: ContributionStore
    let settings: AppSettings

    var body: some View {
        Section("GitHub account") {
            GitHubTokenSection(store: store)
        }

        Section("Contributions") {
            Picker("Automatic refresh", selection: intervalSelection) {
                ForEach(AppSettings.refreshOptions, id: \.self) { minutes in
                    Text(AppSettings.intervalLabel(minutes)).tag(minutes)
                }
            }

            // Only worth saying while an automatic refresh is actually due.
            if store.pausedForLowPower && settings.refreshIntervalMinutes > 0 {
                note("Automatic refresh is paused in Low Power Mode. Use Refresh now to update.", isProblem: false)
            }

            LabeledContent("Last updated") {
                HStack(spacing: 10) {
                    Text(lastUpdatedText)
                        .foregroundStyle(.secondary)
                    Button("Refresh now") { store.refresh() }
                        .controlSize(.small)
                        .disabled(!store.isConnected || store.isLoading)
                }
            }

            if let problem = refreshProblem {
                note(problem, isProblem: true)
            }
        }
    }

    // MARK: Pieces

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
