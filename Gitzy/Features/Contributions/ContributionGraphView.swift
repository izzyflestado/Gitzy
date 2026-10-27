import SwiftUI

/// Sizes and colours of the graph, kept free of SwiftUI state so they can be tested and used while drawing.
nonisolated enum GraphMetrics {
    static let gap: CGFloat = 1.5
    /// A year of weeks. The cell size is worked out for at least this many columns, so the graph never gets taller.
    static let minimumColumns = 53
    static let rows = 7
    /// The fixed height of the graph, so the popover layout never moves.
    static let height: CGFloat = 44

    /// The largest cell (in half points, so lines stay crisp on Retina screens) that fits all columns in `width`.
    static func cellSize(width: CGFloat, columns: Int) -> CGFloat {
        let count = max(columns, minimumColumns)
        let raw = (width - CGFloat(count - 1) * gap) / CGFloat(count)
        return max(2, (raw * 2).rounded(.down) / 2)
    }

    static func gridWidth(cell: CGFloat, columns: Int) -> CGFloat {
        let count = max(columns, minimumColumns)
        return CGFloat(count) * (cell + gap) - gap
    }

    static func rect(column: Int, row: Int, cell: CGFloat) -> CGRect {
        CGRect(
            x: CGFloat(column) * (cell + gap),
            y: CGFloat(row) * (cell + gap),
            width: cell,
            height: cell
        )
    }

    /// GitHub's dark-theme greens. "No contributions" is a faint white so it works on any popover background.
    static func color(for level: ContributionLevel) -> Color {
        switch level {
        case .none: return Color(white: 1, opacity: 0.08)
        case .first: return Color(red: 0x0e / 255, green: 0x44 / 255, blue: 0x29 / 255)
        case .second: return Color(red: 0x00 / 255, green: 0x6d / 255, blue: 0x32 / 255)
        case .third: return Color(red: 0x26 / 255, green: 0xa6 / 255, blue: 0x41 / 255)
        case .fourth: return Color(red: 0x39 / 255, green: 0xd3 / 255, blue: 0x53 / 255)
        }
    }
}

/// The last 12 months as GitHub draws them: one column per week, Sunday at the top.
/// Drawn with shapes in a single Canvas, so there are no images and no per-cell views.
struct ContributionGraphView: View {
    let weeks: [[ContributionDay]]
    let total: Int

    var body: some View {
        let weeks = self.weeks
        Canvas { context, size in
            let cell = GraphMetrics.cellSize(width: size.width, columns: weeks.count)
            let offset = max(0, (size.width - GraphMetrics.gridWidth(cell: cell, columns: weeks.count)) / 2)
            for (column, week) in weeks.enumerated() {
                for day in week where (0..<GraphMetrics.rows).contains(day.weekday) {
                    var rect = GraphMetrics.rect(column: column, row: day.weekday, cell: cell)
                    rect.origin.x += offset
                    context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(GraphMetrics.color(for: day.level)))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: GraphMetrics.height)
        .accessibilityElement()
        .accessibilityLabel("Contribution graph, \(total) contributions in the last year")
    }
}
