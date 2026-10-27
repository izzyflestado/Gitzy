import Foundation
import Testing
@testable import Gitzy

nonisolated struct GitHeadWatcherTests {

    /// Waits for the first value, or gives up after five seconds.
    private func firstHead(from stream: AsyncStream<GitHead>) async -> GitHead? {
        await withTaskGroup(of: GitHead?.self) { group in
            group.addTask {
                for await head in stream { return head }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    @Test func reportsABranchSwitchTheWayGitDoesIt() async throws {
        let temp = try TempFolder()
        let repo = try temp.repo("project")
        let gitDirectory = try #require(GitRepositoryService.gitDirectory(forRepoAt: repo))

        let (stream, continuation) = AsyncStream.makeStream(of: GitHead.self)
        let watcher = try #require(GitHeadWatcher(gitDirectory: gitDirectory, onChange: { head in
            _ = continuation.yield(head)
        }))
        defer { watcher.stop() }

        // Something else changes in the Git directory first. It must not be reported.
        try temp.write("index", to: "project/.git/index")

        // Git writes HEAD.lock, then renames it over HEAD.
        try temp.write("ref: refs/heads/feature\n", to: "project/.git/HEAD.lock")
        let status = rename(gitDirectory.appendingPathComponent("HEAD.lock").path,
                            gitDirectory.appendingPathComponent("HEAD").path)
        #expect(status == 0)

        #expect(await firstHead(from: stream) == .branch("feature"))
    }

    @Test func aMissingGitDirectoryGivesNoWatcher() throws {
        let temp = try TempFolder()
        let missing = temp.root.appendingPathComponent("nowhere/.git")
        #expect(GitHeadWatcher(gitDirectory: missing, onChange: { _ in }) == nil)
    }
}
