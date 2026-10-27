import Foundation

/// A throwaway folder tree under the system temp directory, deleted when the test ends.
/// Marked nonisolated so tests can use it whatever the test target's default isolation is.
nonisolated final class TempFolder {
    let root: URL

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("gitzy-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        root = url.resolvingSymlinksInPath()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    func folder(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ text: String, to path: String) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// A normal repository: `<path>/.git/HEAD`.
    @discardableResult
    func repo(_ path: String, head: String = "ref: refs/heads/main\n") throws -> URL {
        try write(head, to: "\(path)/.git/HEAD")
        return root.appendingPathComponent(path, isDirectory: true)
    }

    /// Paths relative to the temp folder, for easy comparison.
    func relativePaths(_ urls: [URL]) -> [String] {
        // macOS may report /private/var/... where root says /var/..., so anchor on the unique folder name instead.
        let marker = root.lastPathComponent + "/"
        return urls.map { url in
            guard let range = url.path.range(of: marker) else { return url.path }
            return String(url.path[range.upperBound...])
        }
    }
}
