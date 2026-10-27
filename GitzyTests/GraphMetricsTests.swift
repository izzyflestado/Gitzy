import Foundation
import SwiftUI
import Testing
@testable import Gitzy

nonisolated struct GraphMetricsTests {
    private let width: CGFloat = 328   // the popover's content width

    @Test func cellsFitTheWidthForAFullYear() {
        let cell = GraphMetrics.cellSize(width: width, columns: 53)
        #expect(cell == 4.5)
        #expect(GraphMetrics.gridWidth(cell: cell, columns: 53) == 316.5)
        #expect(GraphMetrics.gridWidth(cell: cell, columns: 53) <= width)
    }

    @Test func anExtraColumnStillFits() {
        let cell = GraphMetrics.cellSize(width: width, columns: 54)
        #expect(GraphMetrics.gridWidth(cell: cell, columns: 54) <= width)
    }

    @Test func fewerColumnsNeverMakeTheGraphTaller() {
        #expect(GraphMetrics.cellSize(width: width, columns: 10) == GraphMetrics.cellSize(width: width, columns: 53))
    }

    @Test func cellsNeverShrinkBelowTwoPoints() {
        #expect(GraphMetrics.cellSize(width: 10, columns: 53) == 2)
    }

    @Test func sevenRowsFitTheFixedHeight() {
        let cell = GraphMetrics.cellSize(width: width, columns: 53)
        let rowsHeight = CGFloat(GraphMetrics.rows) * (cell + GraphMetrics.gap) - GraphMetrics.gap
        #expect(rowsHeight <= GraphMetrics.height)
    }

    @Test func cellPositions() {
        let rect = GraphMetrics.rect(column: 2, row: 3, cell: 4.5)
        #expect(rect == CGRect(x: 12, y: 18, width: 4.5, height: 4.5))
        #expect(GraphMetrics.rect(column: 0, row: 0, cell: 4.5).origin == .zero)
    }

    @Test func everyLevelHasItsOwnColour() {
        let levels: [ContributionLevel] = [.none, .first, .second, .third, .fourth]
        let colours = levels.map { GraphMetrics.color(for: $0) }
        for index in colours.indices {
            for other in colours.indices where other > index {
                #expect(colours[index] != colours[other])
            }
        }
    }
}
