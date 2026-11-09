import AppKit
import CoreGraphics

/// What the window list gave back.
nonisolated enum WindowReading: Equatable, Sendable {
    /// The normal windows on screen right now, front-most first. Empty when nothing is open.
    case windows([WindowSample])
    /// macOS did not fill in who owns the windows or where they are. The caller falls back to the front app.
    case unreadable
}

/// Reads which windows are on screen right now, from the window list macOS keeps.
///
/// This needs no permission: owners and positions are public. Window titles and contents are not, and are never read.
/// The list is "on screen only", which already leaves out hidden apps (Cmd-H), minimized windows and every window on
/// another Space. In a fullscreen Space only that Space's windows are in it.
nonisolated enum WindowSnapshot {
    /// Smaller windows (helper windows, tooltips) are left out.
    static let minimumWindowArea: CGFloat = 10_000

    /// - Parameters:
    ///   - display: the display the widget is on, in the window list's coordinates.
    ///   - ownPID: Gitzy's own process. Its windows are left out entirely.
    ///   - appID: the bundle identifier of a process, if it has one.
    static func read(display: CGRect, ownPID: Int32, appID: (Int32) -> String?) -> WindowReading {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return .unreadable
        }
        return samples(from: list, display: display, ownPID: ownPID, appID: appID)
    }

    /// The list is turned into samples here, apart from reading it, so it can be tested with made-up entries.
    static func samples(
        from list: [[String: Any]],
        display: CGRect,
        ownPID: Int32,
        appID: (Int32) -> String?
    ) -> WindowReading {
        guard !list.isEmpty else { return .unreadable }

        var readable = 0
        var result: [WindowSample] = []
        var appIDs: [Int32: String?] = [:]

        for info in list {
            guard let pidNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary) else { continue }
            readable += 1

            // Layer 0 is where normal windows live. The menu bar, the Dock, Spotlight, popovers and
            // floating panels are all above it, and none of them is "an app being visible".
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            guard layer == 0 else { continue }

            let pid = pidNumber.int32Value
            guard pid != ownPID else { continue }

            let shown = bounds.intersection(display)
            guard !shown.isNull, shown.width * shown.height >= minimumWindowArea else { continue }

            let bundleID: String?
            if let known = appIDs[pid] {
                bundleID = known
            } else {
                bundleID = appID(pid)
                appIDs[pid] = bundleID
            }

            result.append(WindowSample(
                id: (info[kCGWindowNumber as String] as? NSNumber)?.intValue ?? -1,
                appID: bundleID,
                bounds: shown,
                alpha: (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            ))
        }

        return readable == 0 ? .unreadable : .windows(result)
    }
}
