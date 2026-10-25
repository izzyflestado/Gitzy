import AppKit
import SkyLightWindow   // The only file in Gitzy that imports SkyLightWindow. Deleting it removes the dependency.

/// How the branch widget ended up above other apps.
enum Elevation {
    case skyLight
    case fallback(reason: String)

    var summary: String {
        switch self {
        case .skyLight:
            return "Elevation: SkyLight (window moved to a high-level space)"
        case .fallback(let reason):
            return "Elevation: fallback panel only. \(reason)"
        }
    }
}

enum SkyLightElevator {
    private static let frameworkPath = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"
    private static let requiredSymbols = [
        "SLSMainConnectionID",
        "SLSSpaceCreate",
        "SLSSpaceSetAbsoluteLevel",
        "SLSShowSpaces",
        "SLSSpaceAddWindowsAndRemoveFromSpaces",
    ]

    /// Moves the window above everything, or reports why it could not.
    /// SkyLightWindow force-unwraps its private symbol lookups and would crash if macOS removed one,
    /// so we check them ourselves before touching the package. The package does not report whether
    /// the move worked, so only a visual test above a fullscreen app proves it.
    static func elevate(_ window: NSWindow) -> Elevation {
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            return .fallback(reason: "The SkyLight framework could not be loaded.")
        }
        defer { dlclose(handle) }

        if let missing = requiredSymbols.first(where: { dlsym(handle, $0) == nil }) {
            return .fallback(reason: "This macOS no longer provides \(missing).")
        }
        guard window.windowNumber > 0 else {
            return .fallback(reason: "The widget window has no window number yet.")
        }

        let skyLight = SkyLightOperator.shared
        guard skyLight.space > 0 else {
            return .fallback(reason: "SkyLight did not create a space.")
        }
        skyLight.delegateWindow(window)
        return .skyLight
    }
}
