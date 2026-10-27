import Foundation

/// A project saved in Gitzy. The path is always the symlink-resolved path, so it doubles as the identity
/// (two ways of reaching the same folder count as one project).
nonisolated struct GitProject: Codable, Hashable, Identifiable, Sendable {
    let path: String

    var id: String { path }
    var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

/// What a repository's HEAD points at.
nonisolated enum GitHead: Equatable, Sendable {
    case branch(String)
    case detached(String)   // short commit id
    case unknown

    var label: String {
        switch self {
        case .branch(let name): return name
        case .detached(let sha): return "detached at \(sha)"
        case .unknown: return "branch unknown"
        }
    }
}

nonisolated struct ProjectStatus: Equatable, Sendable {
    let head: GitHead
    let isMissing: Bool
}

/// One line in the project list.
nonisolated struct ProjectRow: Identifiable, Equatable, Sendable {
    let project: GitProject
    let status: ProjectStatus

    var id: String { project.id }
}
