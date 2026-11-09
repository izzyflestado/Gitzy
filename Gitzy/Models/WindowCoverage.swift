import CoreGraphics
import Foundation

/// One normal window from the macOS window list, in screen coordinates.
nonisolated struct WindowSample: Equatable, Sendable {
    let id: Int
    /// The owning app's bundle identifier. Nil when it could not be found. Such a window still covers others.
    let appID: String?
    let bounds: CGRect
    let alpha: Double
}

/// How much of one app can be seen.
nonisolated struct AppCoverage: Equatable, Sendable {
    let appID: String
    /// The largest share (0 to 1) of any single window of this app that no window in front of it covers.
    let fraction: Double
    /// Some window of this app is uncovered enough, by share and by size, to count as visible.
    let isVisible: Bool
}

/// Works out which apps are visible from the window list: windows in front-to-back order, each one covered by
/// the opaque windows in front of it. Only rectangles are used, so rounded corners and shadows are ignored.
nonisolated enum WindowCoverage {
    /// A window at least this opaque hides what is behind it. A more see-through window does not.
    static let coveringAlpha = 0.9

    /// - Parameters:
    ///   - windows: normal windows, front-most first.
    ///   - minFraction: the share of a window (0 to 1) that must be uncovered for it to count.
    ///   - minVisibleArea: the uncovered part must also be at least this many square points, so a sliver or a
    ///     tiny popup never counts as an app being in view.
    /// - Returns: one entry per app, in the order each app first appears (front to back).
    static func apps(in windows: [WindowSample], minFraction: Double, minVisibleArea: Double) -> [AppCoverage] {
        var order: [String] = []
        var bestFraction: [String: Double] = [:]
        var visible: Set<String> = []
        var inFront: [CGRect] = []

        for window in windows {
            var remaining = [window.bounds]
            for cover in inFront {
                remaining = remaining.flatMap { subtract($0, cover) }
                if remaining.isEmpty { break }
            }
            let uncovered = remaining.reduce(0.0) { $0 + Double($1.width * $1.height) }
            let whole = Double(window.bounds.width * window.bounds.height)
            let fraction = whole > 0 ? uncovered / whole : 0

            if let appID = window.appID {
                if bestFraction[appID] == nil { order.append(appID) }
                bestFraction[appID] = max(bestFraction[appID] ?? 0, fraction)
                if fraction >= minFraction && uncovered >= minVisibleArea { visible.insert(appID) }
            }
            if window.alpha >= coveringAlpha { inFront.append(window.bounds) }
        }

        return order.map { appID in
            AppCoverage(appID: appID, fraction: bestFraction[appID] ?? 0, isVisible: visible.contains(appID))
        }
    }

    /// `rect` with `cut` taken out of it, as up to four rectangles.
    static func subtract(_ rect: CGRect, _ cut: CGRect) -> [CGRect] {
        let overlap = rect.intersection(cut)
        if overlap.isNull || overlap.isEmpty { return [rect] }
        var pieces: [CGRect] = []
        if overlap.minY > rect.minY {
            pieces.append(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap.minY - rect.minY))
        }
        if overlap.maxY < rect.maxY {
            pieces.append(CGRect(x: rect.minX, y: overlap.maxY, width: rect.width, height: rect.maxY - overlap.maxY))
        }
        if overlap.minX > rect.minX {
            pieces.append(CGRect(x: rect.minX, y: overlap.minY, width: overlap.minX - rect.minX, height: overlap.height))
        }
        if overlap.maxX < rect.maxX {
            pieces.append(CGRect(x: overlap.maxX, y: overlap.minY, width: rect.maxX - overlap.maxX, height: overlap.height))
        }
        return pieces
    }
}
