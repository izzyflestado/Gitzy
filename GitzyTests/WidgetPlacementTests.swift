import CoreGraphics
import Testing
@testable import Gitzy

nonisolated struct WidgetPlacementTests {
    private let size = CGSize(width: 120, height: 26)

    /// 1440 x 900 screen with a 24 pt menu bar and an 80 pt Dock at the bottom.
    private let plain = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 80, width: 1440, height: 796),
        notch: nil
    )

    /// 1512 x 982 screen with a 32 pt camera housing centred at x = 756 and a hidden Dock.
    private let notched = ScreenGeometry(
        frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 950),
        notch: ScreenGeometry.Notch(centerX: 756, height: 32)
    )

    private func origin(_ position: WidgetPosition, on screen: ScreenGeometry) -> CGPoint {
        WidgetPlacement.frame(for: position, size: size, on: screen).origin
    }

    @Test func cornersOnAPlainScreen() {
        #expect(origin(.topLeft, on: plain) == CGPoint(x: 8, y: 842))
        #expect(origin(.topRight, on: plain) == CGPoint(x: 1312, y: 842))
        #expect(origin(.bottomLeft, on: plain) == CGPoint(x: 8, y: 88))
        #expect(origin(.bottomRight, on: plain) == CGPoint(x: 1312, y: 88))
    }

    @Test func notchPositionSitsUnderTheCameraHousing() {
        #expect(origin(.notch, on: notched) == CGPoint(x: 696, y: 920))
    }

    @Test func notchPositionFallsBackToTopCentreWithoutANotch() {
        #expect(origin(.notch, on: plain) == CGPoint(x: 660, y: 842))
    }

    @Test func theSizeIsKept() {
        for position in WidgetPosition.allCases {
            #expect(WidgetPlacement.frame(for: position, size: size, on: plain).size == size)
        }
    }

    @Test func everyPositionStaysOnScreen() {
        for screen in [plain, notched] {
            for position in WidgetPosition.allCases {
                let frame = WidgetPlacement.frame(for: position, size: size, on: screen)
                #expect(screen.frame.contains(frame), "\(position)")
            }
        }
    }

    @Test func positionsRoundTripThroughTheirSavedName() {
        for position in WidgetPosition.allCases {
            #expect(WidgetPosition(rawValue: position.rawValue) == position)
        }
        #expect(WidgetPosition(rawValue: "middle") == nil)
        #expect(WidgetPosition.allCases.count == 5)
    }
}
