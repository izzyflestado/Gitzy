import Foundation

/// Decides which code editor to use for a project, and what to hand it.
///
/// With no editor chosen in Settings ("Automatic"), the project decides: an Xcode project or Swift package opens in
/// Xcode, anything else in VS Code. Xcode also does better with the project file than with the bare folder, so that it
/// opens as a real project (with its schemes and targets) rather than as a folder of files.
nonisolated enum IDETarget {
    static let xcodeBundleID = "com.apple.dt.Xcode"
    static let vscodeBundleID = "com.microsoft.VSCode"

    static func isXcode(appAt app: URL) -> Bool {
        Bundle(url: app)?.bundleIdentifier == xcodeBundleID
    }

    // MARK: Automatic choice

    /// True when the top of the folder has an Xcode workspace, an Xcode project or a Package.swift.
    /// Only the top is looked at, so a dependency folder such as Pods/ never makes a web project look like an Xcode one.
    static func isXcodeProject(_ folder: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return false }
        return names.contains { $0.hasSuffix(".xcworkspace") || $0.hasSuffix(".xcodeproj") || $0 == "Package.swift" }
    }

    /// The editors to try, best first, when none has been chosen: the first one that is installed is used.
    static func automaticOrder(forFolder folder: URL) -> [String] {
        isXcodeProject(folder) ? [xcodeBundleID, vscodeBundleID] : [vscodeBundleID, xcodeBundleID]
    }

    // MARK: What to open

    /// For Xcode: the `.xcworkspace` in the top of the folder if there is one, otherwise the `.xcodeproj`.
    /// A folder with neither (a Swift package, say), and every other editor, gets the folder itself.
    static func target(forFolder folder: URL, isXcode: Bool) -> URL {
        guard isXcode, let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else {
            return folder
        }
        let sorted = names.sorted()
        if let workspace = sorted.first(where: { $0.hasSuffix(".xcworkspace") }) {
            return folder.appendingPathComponent(workspace)
        }
        if let project = sorted.first(where: { $0.hasSuffix(".xcodeproj") }) {
            return folder.appendingPathComponent(project)
        }
        return folder
    }
}
