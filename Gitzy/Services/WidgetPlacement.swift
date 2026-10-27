import CoreGraphics

/// The facts about a screen that placement needs, copied out of NSScreen so the maths can be tested.
nonisolated struct ScreenGeometry: Equatable, Sendable {
    /// The camera housing at the top of a notched screen.
    nonisolated struct Notch: Equatable, Sendable {
        let centerX: CGFloat
        let height: CGFloat
    }

    let frame: CGRect
    /// The screen minus the menu bar and the Dock.
    let visibleFrame: CGRect
    let notch: Notch?
}

/// Works out where the widget goes for each of the five positions. Coordinates are AppKit's (origin bottom left).
nonisolated enum WidgetPlacement {
    static let inset: CGFloat = 8
    static let notchGap: CGFloat = 4

    static func frame(for position: WidgetPosition, size: CGSize, on screen: ScreenGeometry) -> CGRect {
        let area = screen.visibleFrame
        let left = area.minX + inset
        let right = area.maxX - size.width - inset
        let top = area.maxY - size.height - inset
        let bottom = area.minY + inset

        let origin: CGPoint
        switch position {
        case .notch:
            if let notch = screen.notch {
                // Centred just under the camera housing.
                origin = CGPoint(
                    x: notch.centerX - size.width / 2,
                    y: screen.frame.maxY - notch.height - notchGap - size.height
                )
            } else {
                // No notch on this screen: top centre, below the menu bar.
                origin = CGPoint(x: area.midX - size.width / 2, y: top)
            }
        case .topLeft:
            origin = CGPoint(x: left, y: top)
        case .topRight:
            origin = CGPoint(x: right, y: top)
        case .bottomLeft:
            origin = CGPoint(x: left, y: bottom)
        case .bottomRight:
            origin = CGPoint(x: right, y: bottom)
        }
        return CGRect(origin: origin, size: size)
    }
}
