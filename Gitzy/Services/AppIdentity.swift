import AppKit
import UniformTypeIdentifiers

/// An app's name and icon, found from its bundle identifier.
enum AppIdentity {
    /// Names are looked up once. Only apps that were found are kept, so an app installed later is still found.
    private static var knownNames: [String: String] = [:]

    static func url(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static func isInstalled(_ bundleID: String) -> Bool {
        url(for: bundleID) != nil
    }

    /// The app's name, the way Finder shows it. The bundle identifier itself when the app is not installed.
    static func name(for bundleID: String) -> String {
        if let known = knownNames[bundleID] { return known }
        guard let appURL = url(for: bundleID) else { return bundleID }
        let name = appURL.deletingPathExtension().lastPathComponent
        knownNames[bundleID] = name
        return name
    }

    static func icon(for bundleID: String) -> NSImage {
        if let appURL = url(for: bundleID) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
