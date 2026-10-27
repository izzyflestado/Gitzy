import Foundation

/// Finds Git repositories inside a folder the user picked. Read-only, and meant to run off the main thread.
nonisolated enum ProjectScanner {
    static let defaultDepth = 3

    private static let skippedNames: Set<String> = ["node_modules", ".build", "Pods", "DerivedData"]

    /// Looks at the chosen folder (level 0) and up to `maxDepth` levels below it.
    /// Hidden folders and the skipped names above are never entered, so `.git` folders are never scanned.
    /// Symbolic links are never followed (that rules out loops), and unreadable folders are skipped.
    /// A repository inside another repository is listed too.
    static func scan(root: URL, maxDepth: Int = ProjectScanner.defaultDepth) -> [URL] {
        var found: [URL] = []
        walk(root, depth: 0, maxDepth: maxDepth, into: &found)
        return found.sorted { $0.path < $1.path }
    }

    private static func walk(_ folder: URL, depth: Int, maxDepth: Int, into found: inout [URL]) {
        if Task.isCancelled { return }
        if GitRepositoryService.isRepository(at: folder) { found.append(folder) }
        guard depth < maxDepth else { return }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return }

        for child in children {
            if skippedNames.contains(child.lastPathComponent) { continue }
            let values = try? child.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            walk(child, depth: depth + 1, maxDepth: maxDepth, into: &found)
        }
    }
}
