import AppKit
import SwiftUI

/// The dot on the bottom right corner of the profile picture, and the card that appears when the pointer is on it.
///
/// Grey: no contributions today at all. Orange: commits were made on this Mac today but today's square on the graph
/// is still empty (maybe not pushed yet). Green: today's square on the graph already has contributions.
/// Nothing is shown until the graph has loaded.
///
/// The card appears at once and is not animated. It does not take mouse events, so it can never get in the way.
/// The row that holds this view needs `.zIndex(1)`, so the card is drawn above the rows under it.
struct TodayStatusDot: View {
    let store: ContributionStore

    @State private var hovering = false

    var body: some View {
        if let today = TodayActivity.make(weeks: store.snapshot?.weeks, local: store.localToday.local) {
            dot(today)
        }
    }

    // MARK: The dot

    /// A 22 point square holds the 13 point dot, so the pointer has something easy to land on.
    private func dot(_ today: TodayActivity) -> some View {
        Circle()
            .fill(Self.color(for: today.level))
            .frame(width: 9, height: 9)
            .padding(2)
            // A ring in the window's colour, so the dot reads as sitting on the corner of the picture.
            .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .overlay(alignment: .topLeading) {
                if hovering {
                    card(today)
                        .offset(x: 14, y: 20)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Today. \(today.headline) GitHub graph: \(today.graphText). This Mac: \(today.localText).")
    }

    static func color(for level: TodayLevel) -> Color {
        switch level {
        case .quiet: return Color.gray
        case .notOnGitHubYet: return Color.orange
        case .onGitHub: return GraphMetrics.color(for: .fourth)
        }
    }

    // MARK: The card

    private func card(_ today: TodayActivity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Self.color(for: today.level))
                    .frame(width: 8, height: 8)
                Text("Today")
                    .font(.system(size: 12, weight: .semibold))
            }

            Divider()

            row("GitHub graph", today.graphText)
            row("This Mac", today.localText)
        }
        .padding(10)
        .frame(width: 236, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.25), radius: 8, y: 3)
        .allowsHitTesting(false)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: 11, weight: .medium))
        }
    }
}
