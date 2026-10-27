import Foundation
import Testing
@testable import Gitzy

nonisolated struct ProjectScannerTests {

    @Test func findsRepositoriesWithinDepthAndSkipsExcludedFolders() throws {
        let temp = try TempFolder()
        try temp.repo("a")                       // level 1
        try temp.repo("work/b")                  // level 2
        try temp.repo("work/deep/c")             // level 3: still included
        try temp.repo("work/deep/more/d")        // level 4: too deep
        try temp.repo("node_modules/pkg")        // skipped folder
        try temp.repo("Pods/lib")                // skipped folder
        try temp.repo("DerivedData/build")       // skipped folder
        try temp.repo(".hidden/secret")          // hidden folder

        let found = ProjectScanner.scan(root: temp.root, maxDepth: 3)
        #expect(temp.relativePaths(found) == ["a", "work/b", "work/deep/c"])
    }

    @Test func listsRepositoriesInsideOtherRepositories() throws {
        let temp = try TempFolder()
        try temp.repo("outer")
        try temp.repo("outer/inner")

        let found = ProjectScanner.scan(root: temp.root)
        #expect(temp.relativePaths(found) == ["outer", "outer/inner"])
    }

    @Test func neverEntersDotGitFolders() throws {
        let temp = try TempFolder()
        try temp.repo("project")
        try temp.repo("project/.git/modules/looks-like-a-repo")

        let found = ProjectScanner.scan(root: temp.root)
        #expect(temp.relativePaths(found) == ["project"])
    }

    @Test func doesNotFollowSymlinkLoops() throws {
        let temp = try TempFolder()
        try temp.repo("project")
        try FileManager.default.createSymbolicLink(
            at: temp.root.appendingPathComponent("loop"),
            withDestinationURL: temp.root
        )
        try FileManager.default.createSymbolicLink(
            at: temp.root.appendingPathComponent("shortcut"),
            withDestinationURL: temp.root.appendingPathComponent("project")
        )

        let found = ProjectScanner.scan(root: temp.root)
        #expect(temp.relativePaths(found) == ["project"])
    }

    @Test func skipsUnreadableFoldersWithoutCrashing() throws {
        let temp = try TempFolder()
        try temp.repo("ok")
        let locked = try temp.folder("locked")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)

        let found = ProjectScanner.scan(root: temp.root)
        #expect(temp.relativePaths(found) == ["ok"])

        // Restore access so the temp folder can be deleted.
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
    }

    @Test func rootItselfCanBeARepository() throws {
        let temp = try TempFolder()
        try temp.write("ref: refs/heads/main\n", to: ".git/HEAD")

        let found = ProjectScanner.scan(root: temp.root)
        #expect(found.count == 1)
        #expect(found.first?.path == temp.root.path)
    }

    @Test func depthZeroOnlyChecksTheRoot() throws {
        let temp = try TempFolder()
        try temp.repo("child")

        #expect(ProjectScanner.scan(root: temp.root, maxDepth: 0).isEmpty)
        #expect(temp.relativePaths(ProjectScanner.scan(root: temp.root, maxDepth: 1)) == ["child"])
    }
}
