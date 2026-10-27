import Foundation
import Testing
@testable import Gitzy

nonisolated struct GitRepositoryServiceTests {

    /// HEAD of the repository in `folder`, following `.git` files the way Gitzy does.
    private func head(of folder: URL) -> GitHead? {
        GitRepositoryService.gitDirectory(forRepoAt: folder).map {
            GitRepositoryService.readHead(inGitDirectory: $0)
        }
    }

    // MARK: Normal repositories

    @Test func normalBranch() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("project")
        #expect(head(of: repo) == .branch("main"))
        #expect(GitRepositoryService.isRepository(at: repo))
    }

    @Test func branchNameWithSlash() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("project", head: "ref: refs/heads/feature/login-page\n")
        #expect(head(of: repo) == .branch("feature/login-page"))
    }

    // MARK: Detached HEAD

    @Test func detachedHeadShowsShortSha() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("project", head: "0123456789abcdef0123456789abcdef01234567\n")
        #expect(head(of: repo) == .detached("0123456"))
    }

    @Test func detachedHeadWithSha256() throws {
        let temp = try TempFolder()
        let sha256 = String(repeating: "ab", count: 32)
        let repo = try temp.repo("project", head: sha256)
        #expect(head(of: repo) == .detached("abababa"))
    }

    // MARK: Worktrees and submodules

    @Test func worktreeWithAbsoluteGitdir() throws {
        let temp = try TempFolder()
        let mainRepo = try temp.repo("main-repo")
        try temp.write("ref: refs/heads/feature/x\n", to: "main-repo/.git/worktrees/wt/HEAD")
        let worktree = try temp.folder("wt")
        try temp.write("gitdir: \(mainRepo.path)/.git/worktrees/wt\n", to: "wt/.git")

        #expect(GitRepositoryService.isRepository(at: worktree))
        #expect(head(of: worktree) == .branch("feature/x"))
        // The main repository keeps its own HEAD.
        #expect(head(of: mainRepo) == .branch("main"))
    }

    @Test func worktreeWithRelativeGitdir() throws {
        let temp = try TempFolder()
        try temp.repo("main-repo")
        try temp.write("ref: refs/heads/topic\n", to: "main-repo/.git/worktrees/wt/HEAD")
        let worktree = try temp.folder("wt")
        try temp.write("gitdir: ../main-repo/.git/worktrees/wt\n", to: "wt/.git")

        #expect(head(of: worktree) == .branch("topic"))
    }

    @Test func submoduleWithRelativeGitdir() throws {
        let temp = try TempFolder()
        try temp.repo("parent")
        try temp.write("ref: refs/heads/dev\n", to: "parent/.git/modules/sub/HEAD")
        let submodule = try temp.folder("parent/sub")
        try temp.write("gitdir: ../.git/modules/sub\n", to: "parent/sub/.git")

        #expect(GitRepositoryService.isRepository(at: submodule))
        #expect(head(of: submodule) == .branch("dev"))
    }

    @Test func detachedHeadInsideSubmodule() throws {
        let temp = try TempFolder()
        try temp.repo("parent")
        try temp.write("fedcba9876543210fedcba9876543210fedcba98\n", to: "parent/.git/modules/sub/HEAD")
        let submodule = try temp.folder("parent/sub")
        try temp.write("gitdir: ../.git/modules/sub\n", to: "parent/sub/.git")

        #expect(head(of: submodule) == .detached("fedcba9"))
    }

    // MARK: Things that are not usable repositories

    @Test func plainFolderIsNotARepository() throws {
        let temp = try TempFolder()
        let folder = try temp.folder("plain")
        #expect(!GitRepositoryService.isRepository(at: folder))
        #expect(GitRepositoryService.gitDirectory(forRepoAt: folder) == nil)
    }

    @Test func gitFolderWithoutHeadIsNotARepository() throws {
        let temp = try TempFolder()
        try temp.folder("broken/.git")
        #expect(!GitRepositoryService.isRepository(at: temp.root.appendingPathComponent("broken")))
    }

    @Test func gitFilePointingNowhereIsNotARepository() throws {
        let temp = try TempFolder()
        let folder = try temp.folder("orphan")
        try temp.write("gitdir: ../does-not-exist\n", to: "orphan/.git")
        #expect(!GitRepositoryService.isRepository(at: folder))
    }

    @Test func gitFileWithoutPointerIsNotARepository() throws {
        let temp = try TempFolder()
        let folder = try temp.folder("junk")
        try temp.write("hello\n", to: "junk/.git")
        #expect(GitRepositoryService.gitDirectory(forRepoAt: folder) == nil)
    }

    // MARK: Odd HEAD contents

    @Test func reftableMarkerIsUnknown() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("project", head: "ref: refs/heads/.invalid\n")
        #expect(head(of: repo) == .unknown)
    }

    @Test func garbageHeadIsUnknown() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("project", head: "not a ref\n")
        #expect(head(of: repo) == .unknown)
    }

    // MARK: Project status and path identity

    @Test func missingFolderIsMarkedMissing() {
        let status = GitRepositoryService.status(ofProjectAt: "/definitely/not/here")
        #expect(status.isMissing)
        #expect(status.head == .unknown)
    }

    @Test func statusReadsTheBranch() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("project", head: "ref: refs/heads/develop\n")
        let status = GitRepositoryService.status(ofProjectAt: repo.path)
        #expect(!status.isMissing)
        #expect(status.head == .branch("develop"))
    }

    @Test func symlinkAndRealFolderHaveTheSameResolvedPath() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("project")
        let link = temp.root.appendingPathComponent("shortcut")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo)

        #expect(GitRepositoryService.resolvedPath(of: link) == GitRepositoryService.resolvedPath(of: repo))
    }
}
