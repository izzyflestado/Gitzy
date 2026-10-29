import Foundation
import os

/// Where Gitzy keeps the GitHub token: one small file that only your user account can read.
///
/// Gitzy used to keep the token in the Keychain. An app signed without an Apple Developer account gets a new
/// signature on every build, and the Keychain ties each item to the signature of the app that saved it. So macOS
/// kept asking for permission, and a refused prompt made the token look lost. A plain private file has neither
/// problem, and it survives restarts, rebuilds and updates.
///
/// The trade-off, in plain words: the Keychain can keep other programs away from the token, a file cannot.
/// Any program running as you can read it. The folder is 0700 and the file is 0600, so other user accounts on
/// the Mac cannot. The token is a classic one with only read:user, so it can only read profile information.
///
/// The token is never logged, and error messages never contain it. Nothing here touches the Keychain.
nonisolated struct TokenFile: Sendable {

    /// What reading the file found. Telling "nothing saved" apart from "could not read it" matters,
    /// because only the first one means the person has to paste a token again.
    nonisolated enum StoredToken: Equatable, Sendable {
        case found(String)
        case missing
        case unreadable

        var token: String? {
            if case .found(let text) = self { return text }
            return nil
        }
    }

    nonisolated struct Failure: Error, Equatable, Sendable {
        /// Plain language, and never contains the token.
        let message: String
    }

    /// A fixed folder name, on purpose. It does not depend on the bundle identifier,
    /// so changing the bundle identifier later cannot orphan a saved token.
    static let folderName = "Gitzy"
    static let fileName = "github-token"

    /// ~/Library/Application Support/Gitzy
    static let standard: TokenFile = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return TokenFile(directory: base.appendingPathComponent(TokenFile.folderName, isDirectory: true))
    }()

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Gitzy", category: "token-file")

    let directory: URL

    var fileURL: URL { directory.appendingPathComponent(Self.fileName) }
    private var temporaryURL: URL { directory.appendingPathComponent(Self.fileName + ".tmp") }

    // MARK: Saving

    /// Saves the token, replacing any earlier one. The file is written next to its final place and then renamed
    /// over it, so a crash half way through can never leave a half-written token behind.
    func save(token: String) throws {
        let manager = FileManager.default
        do {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            // Applies to a folder that already existed too, not only to a new one.
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        } catch {
            throw failure("create its folder", reason: error.localizedDescription)
        }

        // A token should not travel into Time Machine backups. Best effort.
        var folder = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)

        try? manager.removeItem(at: temporaryURL)
        guard manager.createFile(atPath: temporaryURL.path, contents: Data(token.utf8), attributes: [.posixPermissions: 0o600]) else {
            throw failure("write the file", reason: "the file could not be created")
        }
        if rename(temporaryURL.path, fileURL.path) != 0 {
            let reason = String(cString: strerror(errno))
            try? manager.removeItem(at: temporaryURL)
            throw failure("replace the file", reason: reason)
        }
    }

    // MARK: Loading

    func load() -> StoredToken {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return .missing
        } catch {
            return .unreadable
        }
        guard let text = String(data: data, encoding: .utf8) else { return .unreadable }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? .missing : .found(trimmed)
    }

    // MARK: Deleting

    /// Removes the token file (and a leftover temporary one). True when no token file remains,
    /// which includes the case where there was never one. The folder itself is left alone.
    func delete() -> Bool {
        let manager = FileManager.default
        for url in [fileURL, temporaryURL] where manager.fileExists(atPath: url.path) {
            try? manager.removeItem(at: url)
        }
        return !manager.fileExists(atPath: fileURL.path)
    }

    // MARK: Private

    private func failure(_ action: String, reason: String) -> Failure {
        Self.logger.error("Could not \(action, privacy: .public): \(reason, privacy: .private)")
        return Failure(message: "Gitzy could not \(action) (\(reason)).")
    }
}
