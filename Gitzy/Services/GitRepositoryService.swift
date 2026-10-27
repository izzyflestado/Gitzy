import Foundation

/// Reads Git repositories straight from their files. It never starts a git process and never writes anything.
nonisolated enum GitRepositoryService {

    /// The path used to compare projects: symlinks resolved, so two routes to one folder match.
    static func resolvedPath(of folder: URL) -> String {
        folder.resolvingSymlinksInPath().path
    }

    /// True when the folder has a usable `.git` (a directory, or a file pointing to one) that contains a HEAD file.
    static func isRepository(at folder: URL) -> Bool {
        guard let gitDir = gitDirectory(forRepoAt: folder) else { return false }
        return FileManager.default.fileExists(atPath: gitDir.appendingPathComponent("HEAD").path)
    }

    /// Where Git keeps this repository's HEAD.
    /// Normal repository: `<folder>/.git` is a directory.
    /// Worktree or submodule: `.git` is a small file containing `gitdir: <path>`, and the path
    /// (absolute, or relative to the folder) is that worktree's or submodule's own Git directory.
    static func gitDirectory(forRepoAt folder: URL) -> URL? {
        // Mark the folder as a directory, otherwise a relative `gitdir:` would resolve one level too high.
        let folder = URL(fileURLWithPath: folder.path, isDirectory: true)
        let dotGit = folder.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return dotGit }

        guard let text = try? String(contentsOf: dotGit, encoding: .utf8) else { return nil }
        let prefix = "gitdir:"
        guard let line = text.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix(prefix) }) else { return nil }
        let pointer = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard !pointer.isEmpty else { return nil }

        // An absolute path ignores `folder`; a relative one is resolved against it.
        return URL(fileURLWithPath: pointer, relativeTo: folder).standardizedFileURL
    }

    /// Parses HEAD: `ref: refs/heads/<branch>` is a branch, a bare commit id is a detached HEAD.
    static func readHead(inGitDirectory gitDir: URL) -> GitHead {
        guard let text = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8) else {
            return .unknown
        }
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if content.hasPrefix("ref:") {
            let ref = content.dropFirst(4).trimmingCharacters(in: .whitespaces)
            let branchPrefix = "refs/heads/"
            guard ref.hasPrefix(branchPrefix) else { return .unknown }
            let name = String(ref.dropFirst(branchPrefix.count))
            // ".invalid" is what newer Git writes when the real HEAD lives in its reftable storage, which Gitzy cannot read.
            return name.isEmpty || name == ".invalid" ? .unknown : .branch(name)
        }
        if isObjectID(content) { return .detached(String(content.prefix(7))) }
        return .unknown
    }

    /// Everything the project list needs to show for one saved path.
    static func status(ofProjectAt path: String) -> ProjectStatus {
        guard FileManager.default.fileExists(atPath: path) else {
            return ProjectStatus(head: .unknown, isMissing: true)
        }
        let folder = URL(fileURLWithPath: path, isDirectory: true)
        guard let gitDir = gitDirectory(forRepoAt: folder) else {
            return ProjectStatus(head: .unknown, isMissing: false)
        }
        return ProjectStatus(head: readHead(inGitDirectory: gitDir), isMissing: false)
    }

    private static func isObjectID(_ text: String) -> Bool {
        (text.count == 40 || text.count == 64) && text.allSatisfy(\.isHexDigit)
    }
}
