import AppKit
import SwiftUI

/// The GitHub tab: who you are, your streak, the graph, and how many contributions you have made this year.
///
/// The token field and the automatic-refresh choice are not here any more. They move into the Settings window.
/// Until that exists, GitHubTokenSection is shown by the popover only while there is no working token.
///
/// "No animation" is applied piece by piece rather than once at the top, so the refresh icon is free to spin.
struct ContributionsTestView: View {
    let store: ContributionStore

    /// Every press of Refresh adds one full turn, which is what makes the icon spin once.
    @State private var refreshTurns = 0

    private let avatarSize: CGFloat = 36

    var body: some View {
        if store.isConnected {
            connected
        } else {
            notConnected
        }
    }

    // MARK: Connected

    private var connected: some View {
        VStack(alignment: .leading, spacing: 10) {
            profile
                .transaction { $0.animation = nil }
            summary
            graph
                .transaction { $0.animation = nil }
            total
                .transaction { $0.animation = nil }
            statusLines
                .transaction { $0.animation = nil }
        }
    }

    // MARK: Profile

    private var profile: some View {
        HStack(spacing: 10) {
            avatarView
            VStack(alignment: .leading, spacing: 1) {
                Text(primaryName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let secondary = secondaryName {
                    Text(secondary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: avatarSize)
    }

    private var avatarView: some View {
        Group {
            if let image = store.avatar {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
        .accessibilityHidden(true)
    }

    /// The display name when there is one, otherwise the user name.
    private var primaryName: String {
        store.snapshot?.name ?? "@\(store.login ?? "")"
    }

    /// The user name under the display name. Not repeated when it is already the main line.
    private var secondaryName: String? {
        store.snapshot?.name == nil ? nil : "@\(store.login ?? "")"
    }

    // MARK: Streak and refresh

    private var summary: some View {
        HStack(alignment: .bottom) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(streakText)
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                Text("day streak")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .transaction { $0.animation = nil }

            Spacer()
            refreshButton
        }
        .frame(height: 44, alignment: .bottom)
    }

    private var refreshButton: some View {
        Button {
            refreshTurns += 1
            store.refresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(Double(refreshTurns) * 360))
                .animation(.linear(duration: 1), value: refreshTurns)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.borderless)
        .disabled(store.isLoading)
        .help("Refresh contributions")
        .accessibilityLabel("Refresh contributions")
    }

    // MARK: Graph and count

    @ViewBuilder private var graph: some View {
        if let snapshot = store.snapshot {
            ContributionGraphView(weeks: snapshot.weeks, total: snapshot.totalContributions)
        } else {
            Color.clear.frame(height: GraphMetrics.height)
        }
    }

    /// Bottom right of the graph. Fixed height, so it never moves anything when the data arrives.
    private var total: some View {
        Text(totalText)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .frame(height: 14)
    }

    // MARK: Status

    /// Two fixed lines, so showing or hiding a message never moves anything below it.
    private var statusLines: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(status.text)
                .foregroundStyle(status.isWarning ? Color.orange : Color.secondary)
                .lineLimit(2)
            Text(lastUpdatedLine)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.system(size: 11))
        .frame(height: 44, alignment: .topLeading)
    }

    // MARK: Not connected

    private var notConnected: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("Not connected to GitHub")
                .font(.system(size: 13, weight: .medium))
            Text("Add a token below to see your streak and contributions.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .transaction { $0.animation = nil }
    }

    // MARK: Text

    private var streakText: String {
        guard let snapshot = store.snapshot else { return "–" }
        return String(snapshot.currentStreak)
    }

    /// "1,234 contributions in 2026": from January 1 of the newest year in the graph up to today.
    private var totalText: String {
        guard let snapshot = store.snapshot, let year = snapshot.currentYear else { return "" }
        let count = snapshot.contributionsThisYear
        let number = count.formatted()
        return count == 1 ? "\(number) contribution in \(year)" : "\(number) contributions in \(year)"
    }

    private var status: (text: String, isWarning: Bool) {
        if store.isLoading { return ("Loading…", false) }
        if let error = store.refreshError { return (error, true) }
        if let warning = store.tokenWarning { return (warning, true) }
        if store.pausedForLowPower { return ("Automatic refresh is paused in Low Power Mode.", false) }
        if store.snapshot == nil { return ("No data yet.", false) }
        return ("", false)
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
