import Foundation

/// Decides what to hand to a code editor when it is asked to open a project.
///
/// VS Code and most editors take the project folder. Xcode does better with the project file inside it,
/// so that it opens as a real project (with its schemes and targets) rather than as a folder of files.
nonisolated enum IDETarget {
    static let xcodeBundleID = "com.apple.dt.Xcode"

    static func isXcode(appAt app: URL) -> Bool {
        Bundle(url: app)?.bundleIdentifier == xcodeBundleID
    }

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
