import AppKit
import SwiftUI

/// "Recent activity" under the contribution graph: what you did on GitHub lately, in the style of the summary on a
/// GitHub profile ("Made 3 commits", "Opened pull request"...).
///
/// Five rows are visible. The list scrolls, and "Load more" asks GitHub for the next 30 days or so.
/// A click on a row opens that pull request, issue or repository in the browser.
struct RecentActivityView: View {
    let activity: RecentActivityStore

    /// Change these two to change how tall the list is.
    private static let visibleRows = 5
    private static let rowHeight: CGFloat = 40

    var body: some View {
        // Nothing at all until a load has started, so a failed contribution refresh does not leave an empty heading.
        if activity.isLoading || activity.hasLoaded || !activity.items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                header
                content
            }
            .padding(.bottom, 12)
            .transaction { $0.animation = nil }
        }
    }

    // MARK: Pieces

    /// Fixed height, so the spinner appearing and disappearing moves nothing.
    private var header: some View {
        HStack(spacing: 6) {
            Text("Recent activity")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            if activity.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(height: 18)
    }

    @ViewBuilder private var content: some View {
        if !activity.items.isEmpty {
            list
            if let error = activity.error {
                errorLine(error)
            }
            if activity.hasMore {
                loadMoreButton
            }
        } else if let error = activity.error {
            errorLine(error)
            Button("Try again") { activity.retry() }
                .controlSize(.small)
                .disabled(activity.isLoading)
        } else if activity.hasLoaded {
            note(emptyText)
            if activity.hasMore {
                loadMoreButton
            }
        } else {
            note("Loading…")
        }
    }

    /// Exactly `visibleRows` rows tall once there are that many, and scrolls from there.
    private var list: some View {
        let rows = min(activity.items.count, Self.visibleRows)
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(activity.items) { item in
                    ActivityRow(item: item)
                        .frame(height: Self.rowHeight)
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: CGFloat(rows) * Self.rowHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private var loadMoreButton: some View {
        Button {
            activity.loadMore()
        } label: {
            Text("Load more")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(activity.isLoading)
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
        activity.daysCovered >= ActivityWindows.maxDaysBack - 1
            ? "No activity in the last year."
            : "No activity in the last \(max(activity.daysCovered, 1)) days."
    }
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
                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: 6)

                Text(dateText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(hovering && item.url != nil ? Color.primary.opacity(0.07) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(item.url == nil)
        .onHover { hovering = $0 }
        .help("Open on GitHub")
        .accessibilityLabel("\(item.action), \(item.subtitle), \(dateText)")
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
