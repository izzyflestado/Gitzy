import AppKit
import SwiftUI

/// The GitHub tab: who you are (with the profile and refresh icons), your streak with this year's contributions
/// at its right, and the graph.
///
/// The token field, the automatic-refresh choice and the last-updated time live in the Settings window.
/// When there is no token, or GitHub has refused it, this tab points there through `openSettings`.
///
/// "No animation" is applied piece by piece rather than once at the top, so the refresh icon is free to spin.
struct ContributionsTestView: View {
    let store: ContributionStore
    /// Opens the Settings window. The not-connected screen and a rejected token both send people there.
    let openSettings: () -> Void

    /// Every press of Refresh adds one full turn, which is what makes the icon spin once.
    @State private var refreshTurns = 0

    private let avatarSize: CGFloat = 38

    var body: some View {
        if store.isConnected {
            connected
        } else {
            notConnected
        }
    }

    // MARK: Connected

    private var connected: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileRow
            summary
                .padding(.top, 14)
                .transaction { $0.animation = nil }
            graph
                .padding(.top, 6)
                .transaction { $0.animation = nil }
            problemLine
                .transaction { $0.animation = nil }
            RecentActivityView(activity: store.activity)
                .padding(.top, 14)
        }
    }
    
    // MARK: Profile and refresh

    private var profileRow: some View {
        HStack(spacing: 10) {
            avatarView
            Text(usernameText)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .transaction { $0.animation = nil }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                profileButton
                refreshButton
            }
        }
        .frame(height: avatarSize)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .padding(.top, 8)
        // Above the rows under it, so the card that opens from the dot on the picture is not drawn over by them.
        .zIndex(1)
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
        // Outside the round clip, on the bottom right corner. It also shows today's numbers when the pointer is on it.
        .overlay(alignment: .bottomTrailing) {
            TodayStatusDot(store: store)
                .offset(x: 6, y: 6)
        }
    }

    /// The user name with its @. It is the only name shown, so the row stays short.
    private var usernameText: String {
        "@\(store.login ?? "")"
    }

    private var refreshButton: some View {
        Button {
            refreshTurns += 1
            store.refresh()
        } label: {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(Double(refreshTurns) * 360))
                .animation(.linear(duration: 1), value: refreshTurns)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .disabled(store.isLoading)
        .help("Refresh contributions")
        .accessibilityLabel("Refresh contributions")
    }
    
    /// Opens your GitHub page in the default browser.
    private var profileButton: some View {
        Button {
            if let url = profileURL { NSWorkspace.shared.open(url) }
        } label: {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderless)
        .disabled(profileURL == nil)
        .help("Open @\(store.login ?? "") on GitHub")
        .accessibilityLabel("Open GitHub profile")
    }

    /// https://github.com/<user name>. The user name came from the network, so it is only used when it is made of
    /// the characters GitHub allows in one. Anything else gives no link, and the button stays grayed out.
    private var profileURL: URL? {
        guard let login = store.login, !login.isEmpty, login.count <= 64,
              login.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return URL(string: "https://github.com/\(login)")
    }

    // MARK: Streak and yearly count

    /// The streak on the left, and the yearly count at the top right of the graph.
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

    // MARK: Graph

    @ViewBuilder private var graph: some View {
        if let snapshot = store.snapshot {
            ContributionGraphView(weeks: snapshot.weeks, total: snapshot.totalContributions)
        } else {
            Color.clear.frame(height: GraphMetrics.height)
        }
    }

    /// Bottom left of the graph. Fixed height, so it never moves anything when the data arrives.
    private var lastUpdated: some View {
        Text(lastUpdatedLine)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 14)
    }

    // MARK: Status

    /// Only shown when something is wrong (a failed refresh, a rate limit, a token warning). Normally it takes no space.
    @ViewBuilder private var problemLine: some View {
        if !store.isLoading, let text = store.refreshError ?? store.tokenWarning {
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                // No refresh error means the line is showing the token warning, which also needs a new token.
                if store.tokenRejected || store.refreshError == nil {
                    Button("Open Settings", action: openSettings)
                        .controlSize(.small)
                }
            }
            .padding(.top, 10)
        }
    }

    // MARK: Not connected

    private var notConnected: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 30))
                .foregroundStyle(.tertiary)
            Text("Not connected to GitHub")
                .font(.system(size: 13, weight: .medium))
            Text("Add a token in Settings to see your streak and contributions.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings", action: openSettings)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
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
        let day = snapshot.fetchedAt.formatted(.dateTime.month(.abbreviated).day())
        return "Last updated \(day), \(time)"
    }
}
