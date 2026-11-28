import AppKit
import SwiftUI

/// "Recent activity" under the contribution graph, from one of two places the person picks at the right of the heading.
///
/// GitHub: what you did on GitHub lately, in the style of the summary on a GitHub profile ("Made 3 commits",
/// "Opened pull request"...). "Load more" asks GitHub for the next 30 days or so.
/// Local: every commit made on this Mac in the saved projects over the last 30 days, one row each. "Load more" shows more of them.
///
/// Five rows are visible and the list scrolls. A click on a GitHub row opens that pull request, issue or repository in the browser.
struct RecentActivityView: View {
    let activity: RecentActivityStore
    let local: LocalActivityStore

    /// Which list shows. Remembered between launches.
    @AppStorage("recentActivitySource") private var sourceName = ActivitySource.github.rawValue

    /// Change these two to change how tall the list is.
    private static let visibleRows = 5
    private static let rowHeight: CGFloat = 40

    private var source: ActivitySource { ActivitySource(rawValue: sourceName) ?? .github }

    var body: some View {
        // Nothing at all until a load has started, so a failed contribution refresh does not leave an empty heading.
        if source == .local || activity.isLoading || activity.hasLoaded || !activity.items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                header
                content
            }
            .padding(.bottom, 12)
            .transaction { $0.animation = nil }
            .onChange(of: sourceName) { _, _ in
                if source == .local { local.refresh() }
            }
        }
    }

    // MARK: What the chosen source gives

    private var items: [ActivityItem] { source == .local ? local.items : activity.items }
    private var isLoading: Bool { source == .local ? local.isLoading : activity.isLoading }
    private var hasLoaded: Bool { source == .local ? local.hasLoaded : activity.hasLoaded }
    private var hasMore: Bool { source == .local ? local.hasMore : activity.hasMore }
    private var error: String? { source == .local ? nil : activity.error }

    private func loadMore() {
        if source == .local { local.loadMore() } else { activity.loadMore() }
    }

    // MARK: Pieces

    /// Fixed height, so the spinner appearing and disappearing moves nothing.
    private var header: some View {
        HStack(spacing: 6) {
            Text("Recent activity")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Picker("Source", selection: $sourceName) {
                ForEach(ActivitySource.allCases) { option in
                    Text(option.title).tag(option.rawValue)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
        }
        .frame(height: 18)
    }

    @ViewBuilder private var content: some View {
        if !items.isEmpty {
            list
            if let error {
                errorLine(error)
            }
            if hasMore {
                loadMoreButton
            }
        } else if let error {
            errorLine(error)
            Button("Try again") { activity.retry() }
                .controlSize(.small)
                .disabled(activity.isLoading)
        } else if hasLoaded {
            note(emptyText)
            if hasMore {
                loadMoreButton
            }
        } else {
            note("Loading…")
        }
    }

    /// Exactly `visibleRows` rows tall once there are that many, and scrolls from there.
    /// No box around it. A thin line sits between each row, and none after the last one.
    private var list: some View {
        let rows = min(items.count, Self.visibleRows)
        let lastID = items.last?.id
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    ActivityRow(item: item)
                        .frame(height: Self.rowHeight)
                        .overlay(alignment: .bottom) {
                            if item.id != lastID {
                                Color.primary.opacity(0.12)
                                    .frame(height: 1)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: CGFloat(rows) * Self.rowHeight)
    }

    private var loadMoreButton: some View {
        Button {
            loadMore()
        } label: {
            Text("Load more")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(isLoading)
    }

    private func errorLine(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color.orange)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyText: String {
        if source == .local {
            return "No commits in your saved projects in the last \(LocalCommits.days) days."
        }
        return activity.daysCovered >= ActivityWindows.maxDaysBack - 1
            ? "No activity in the last year."
            : "No activity in the last \(max(activity.daysCovered, 1)) days."
    }
}

/// Where "Recent activity" comes from.
private enum ActivitySource: String, CaseIterable, Identifiable {
    case github
    case local

    var id: String { rawValue }
    var title: String { self == .github ? "GitHub" : "Local" }
}

/// One row: an icon for the kind, the action and where, and when. Clicking opens it on GitHub.
private struct ActivityRow: View {
    let item: ActivityItem

    @State private var hovering = false

    var body: some View {
        Button {
            if let url = item.url { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.action)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(item.commitMessage == nil ? item.subtitle : "commit")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 6)

                if item.commitMessage == nil {
                    Text(dateText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .layoutPriority(1)
                } else {
                    // A single commit: the repository moves to the right, above the date.
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(item.repo)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(dateText)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 130, alignment: .trailing)
                    .layoutPriority(1)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering && item.url != nil ? Color.primary.opacity(0.07) : Color.clear)
                    .padding(.vertical, 2)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.url == nil ? "" : "Open on GitHub")
        .accessibilityLabel(item.commitMessage == nil
                ? "\(item.action), \(item.subtitle), \(dateText)"
                : "Commit: \(item.action), \(item.repo), \(dateText)")
    }

    private var dateText: String {
        ActivityDateLabel.text(for: item.date)
    }

    private var symbol: String {
        switch item.kind {
        case .commits: return "arrow.triangle.branch"
        case .pullRequest: return "arrow.triangle.pull"
        case .issue: return "exclamationmark.circle"
        case .review: return "text.bubble"
        case .repository: return "book.closed"
        }
    }
}
