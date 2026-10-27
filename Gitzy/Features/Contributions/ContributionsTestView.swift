import SwiftUI

/// Milestone 4 test UI: the streak, the graph and the refresh controls.
/// The final Contributions tab arrives in Milestone 5 and reuses ContributionGraphView.
struct ContributionsTestView: View {
    let store: ContributionStore
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            summary
            graph
            statusLines
            controls
            yearCheck
        }
    }

    // MARK: Pieces

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(streakText)
                .font(.system(size: 34, weight: .semibold).monospacedDigit())
            Text("day streak")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Text(totalText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(height: 44, alignment: .bottom)
    }

    @ViewBuilder private var graph: some View {
        if let snapshot = store.snapshot {
            ContributionGraphView(weeks: snapshot.weeks, total: snapshot.totalContributions)
        } else {
            Color.clear.frame(height: GraphMetrics.height)
        }
    }

    /// Two fixed lines, so showing or hiding a message never moves anything below it.
    private var statusLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(firstStatusLine)
                .foregroundStyle(store.refreshError == nil ? Color.secondary : Color.orange)
                .lineLimit(2)
            Text(lastUpdatedLine)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .frame(height: 44, alignment: .topLeading)
    }

    private var controls: some View {
        HStack {
            Button("Refresh") { store.refresh() }
                .disabled(!store.isConnected || store.isLoading)
            Spacer()
            Text("Auto refresh")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Picker("Auto refresh", selection: Binding(
                get: { settings.refreshIntervalMinutes },
                set: { store.setRefreshInterval($0) }
            )) {
                ForEach(AppSettings.refreshOptions, id: \.self) { minutes in
                    Text(AppSettings.intervalLabel(minutes)).tag(minutes)
                }
            }
            .labelsHidden()
            .frame(width: 110)
        }
        .controlSize(.small)
    }

    /// Milestone 4 test only: proves the earlier-years request works against the real GitHub.
    private var yearCheck: some View {
        HStack(alignment: .top, spacing: 8) {
            Button("Test earlier years") { store.checkEarlierYears() }
                .controlSize(.small)
                .disabled(!store.isConnected || store.snapshot == nil || store.isCheckingYears)
            Text(store.yearCheckText ?? "")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(height: 30, alignment: .topLeading)
    }

    // MARK: Text

    private var streakText: String {
        guard let snapshot = store.snapshot else { return "–" }
        return String(snapshot.currentStreak)
    }

    private var totalText: String {
        guard let snapshot = store.snapshot else { return "" }
        let count = snapshot.totalContributions.formatted()
        return snapshot.totalContributions == 1
            ? "\(count) contribution in the last year"
            : "\(count) contributions in the last year"
    }

    private var firstStatusLine: String {
        if !store.isConnected { return "Not connected. Add a token below." }
        if store.isLoading { return "Loading…" }
        if let error = store.refreshError { return error }
        if store.pausedForLowPower { return "Automatic refresh is paused in Low Power Mode." }
        if store.snapshot == nil { return "No data yet." }
        return ""
    }

    private var lastUpdatedLine: String {
        guard let snapshot = store.snapshot else { return "" }
        let time = snapshot.fetchedAt.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(snapshot.fetchedAt) {
            return "Last updated \(time)"
        }
        return "Last updated \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .omitted)), \(time)"
    }
}
