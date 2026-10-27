import Foundation

/// Tells you when a repository's HEAD changes, without any timer.
///
/// Git never edits HEAD in place: it writes HEAD.lock and renames it over HEAD. That shows up as a change to
/// the Git directory itself, so the directory is what gets watched. Many other things also change it
/// (the index, for example), so every event re-reads HEAD, which is a few bytes, and only a real change is reported.
/// Nothing here runs git, and nothing here writes anything.
nonisolated final class GitHeadWatcher: @unchecked Sendable {
    private let queue = DispatchQueue(label: "gitzy.head-watcher", qos: .utility)
    private let gitDirectory: URL
    private let onChange: @Sendable (GitHead) -> Void
    private let source: DispatchSourceFileSystemObject
    /// Only touched on `queue` once the watcher is running.
    private var lastHead: GitHead

    /// Nil when the Git directory cannot be opened.
    init?(gitDirectory: URL, onChange: @escaping @Sendable (GitHead) -> Void) {
        let descriptor = open(gitDirectory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }

        self.gitDirectory = gitDirectory
        self.onChange = onChange
        lastHead = GitRepositoryService.readHead(inGitDirectory: gitDirectory)
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.check() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    deinit {
        source.cancel()
    }

    func stop() {
        source.cancel()
    }

    private func check() {
        let head = GitRepositoryService.readHead(inGitDirectory: gitDirectory)
        guard head != lastHead else { return }
        lastHead = head
        onChange(head)
    }
}
