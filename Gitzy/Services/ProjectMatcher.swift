import Foundation

/// Decides which saved project an editor's open file or folder belongs to.
/// The widget only ever shows saved projects, so anything else matches nothing.
nonisolated enum ProjectMatcher {
    /// The saved project that is `path` itself or one of its parent folders. The deepest one wins,
    /// so a project nested inside another is picked over the outer one.
    /// Folders are compared name by name, so /a/app never matches /a/app-two.
    static func match(path: String, in projects: [String]) -> String? {
        let target = components(of: path)
        var best: (path: String, depth: Int)?
        for project in projects {
            let parts = components(of: project)
            guard !parts.isEmpty, parts.count <= target.count, Array(target.prefix(parts.count)) == parts else { continue }
            if parts.count > (best?.depth ?? -1) {
                best = (project, parts.count)
            }
        }
        return best?.path
    }

    private static func components(of path: String) -> [String] {
        path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    }
}
