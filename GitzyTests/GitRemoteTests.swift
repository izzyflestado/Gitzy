import Foundation
import Testing
@testable import Gitzy

nonisolated struct GitRemoteTests {

    private func page(_ remote: String) -> String? {
        GitRemote.githubURL(fromRemote: remote)?.absoluteString
    }

    private func configPage(_ text: String) -> String? {
        GitRemote.githubURL(fromConfig: text)?.absoluteString
    }

    // MARK: One remote address

    @Test func httpsAddress() {
        #expect(page("https://github.com/octocat/hello") == "https://github.com/octocat/hello")
        #expect(page("https://github.com/octocat/hello.git") == "https://github.com/octocat/hello")
        #expect(page("https://github.com/octocat/hello/") == "https://github.com/octocat/hello")
        #expect(page("http://github.com/octocat/hello.git") == "https://github.com/octocat/hello")
    }

    @Test func shortSshAddress() {
        #expect(page("git@github.com:octocat/hello.git") == "https://github.com/octocat/hello")
        #expect(page("git@github.com:octocat/hello") == "https://github.com/octocat/hello")
        #expect(page("github.com:octocat/hello.git") == "https://github.com/octocat/hello")
    }

    @Test func sshAndGitSchemes() {
        #expect(page("ssh://git@github.com/octocat/hello.git") == "https://github.com/octocat/hello")
        #expect(page("ssh://git@github.com:22/octocat/hello.git") == "https://github.com/octocat/hello")
        #expect(page("ssh://git@ssh.github.com:443/octocat/hello.git") == "https://github.com/octocat/hello")
        #expect(page("git://github.com/octocat/hello.git") == "https://github.com/octocat/hello")
    }

    @Test func hostAndSchemeAreNotCaseSensitive() {
        #expect(page("HTTPS://GitHub.com/octocat/Hello.git") == "https://github.com/octocat/Hello")
    }

    @Test func namesKeepTheirCase() {
        #expect(page("https://github.com/OctoCat/Hello-World.git") == "https://github.com/OctoCat/Hello-World")
    }

    @Test func repositoryNamesWithDotsAndUnderscores() {
        #expect(page("https://github.com/octocat/hello.world_v2.git") == "https://github.com/octocat/hello.world_v2")
        #expect(page("https://github.com/octocat/.github.git") == "https://github.com/octocat/.github")
        #expect(page("https://github.com/octocat/octocat.github.io") == "https://github.com/octocat/octocat.github.io")
    }

    // MARK: Credentials

    @Test func credentialsNeverReachTheAddress() {
        let remote = "https://octocat:hunter2@github.com/octocat/hello.git"
        let result = page(remote)
        #expect(result == "https://github.com/octocat/hello")
        #expect(result?.contains("hunter2") == false)
        #expect(result?.contains("@") == false)
    }

    @Test func tokenAsUserNameIsDropped() {
        let result = page("https://sometoken@github.com/octocat/hello.git")
        #expect(result == "https://github.com/octocat/hello")
        #expect(result?.contains("sometoken") == false)
    }

    @Test func passwordContainingAtSignIsDropped() {
        #expect(page("https://octocat:p@ss@github.com/octocat/hello.git") == "https://github.com/octocat/hello")
    }

    // MARK: Things that are not GitHub

    @Test func otherHostsGiveNothing() {
        #expect(page("https://gitlab.com/octocat/hello.git") == nil)
        #expect(page("git@bitbucket.org:octocat/hello.git") == nil)
        #expect(page("https://github.example.com/octocat/hello.git") == nil)
        #expect(page("https://github.com.evil.example/octocat/hello.git") == nil)
        #expect(page("https://evilgithub.com/octocat/hello.git") == nil)
        #expect(page("https://evil.example/github.com/octocat/hello") == nil)
        // The host is whatever follows the last @, so this one is evil.example and not github.com.
        #expect(page("https://github.com@evil.example/octocat/hello.git") == nil)
    }

    @Test func localPathsAndOtherSchemesGiveNothing() {
        #expect(page("/Users/me/projects/hello") == nil)
        #expect(page("../hello") == nil)
        #expect(page("file:///Users/me/hello.git") == nil)
        #expect(page("ftp://github.com/octocat/hello.git") == nil)
        #expect(page("javascript://github.com/octocat/hello") == nil)
        #expect(page("") == nil)
    }

    @Test func unusualOwnerOrRepositoryNamesGiveNothing() {
        #expect(page("https://github.com/octocat") == nil)
        #expect(page("https://github.com/octocat/hello/tree/main") == nil)
        #expect(page("https://github.com/octocat/re po") == nil)
        #expect(page("https://github.com/oct%20cat/hello") == nil)
        #expect(page("https://github.com/octocat/hel%6Co") == nil)
        #expect(page("https://github.com/../hello") == nil)
        #expect(page("https://github.com/octocat/..") == nil)
        #expect(page("https://github.com/octocat/.git") == nil)
        #expect(page("https://github.com/öctocat/hello") == nil)
        #expect(page("https://github.com/octocat/hellö") == nil)
        #expect(page("https://github.com/octo\"cat/hello") == nil)
    }

    @Test func queryAndFragmentAreNotPartOfTheName() {
        #expect(page("https://github.com/octocat/hello.git?x=1") == "https://github.com/octocat/hello")
        #expect(page("https://github.com/octocat/hello#readme") == "https://github.com/octocat/hello")
    }

    // MARK: The config text

    @Test func readsOriginFromARealLookingConfig() {
        let text = """
        [core]
        \trepositoryformatversion = 0
        \tbare = false
        [remote "origin"]
        \turl = git@github.com:octocat/hello.git
        \tfetch = +refs/heads/*:refs/remotes/origin/*
        [branch "main"]
        \tremote = origin
        \tmerge = refs/heads/main
        """
        #expect(configPage(text) == "https://github.com/octocat/hello")
    }

    @Test func originWinsOverAnEarlierRemote() {
        let text = """
        [remote "upstream"]
        \turl = https://github.com/someone/hello.git
        [remote "origin"]
        \turl = https://github.com/octocat/hello.git
        """
        #expect(configPage(text) == "https://github.com/octocat/hello")
    }

    @Test func anotherGitHubRemoteIsUsedWhenOriginIsElsewhere() {
        let text = """
        [remote "origin"]
        \turl = https://gitlab.com/octocat/hello.git
        [remote "backup"]
        \turl = https://github.com/octocat/hello.git
        """
        #expect(configPage(text) == "https://github.com/octocat/hello")
    }

    @Test func noGitHubRemoteGivesNothing() {
        let text = """
        [remote "origin"]
        \turl = https://gitlab.com/octocat/hello.git
        """
        #expect(configPage(text) == nil)
        #expect(configPage("") == nil)
        #expect(configPage("[core]\n\tbare = false\n") == nil)
    }

    @Test func urlsOutsideRemoteSectionsAreIgnored() {
        let text = """
        [submodule "x"]
        \turl = https://github.com/octocat/not-this-one.git
        [branch "main"]
        \turl = https://github.com/octocat/nor-this.git
        """
        #expect(configPage(text) == nil)
    }

    @Test func pushUrlIsNotUsed() {
        let text = """
        [remote "origin"]
        \tpushurl = https://github.com/octocat/hello.git
        """
        #expect(configPage(text) == nil)
    }

    @Test func keysAreNotCaseSensitiveAndValuesMayBeQuoted() {
        #expect(configPage("[remote \"origin\"]\n\tURL = https://github.com/octocat/hello.git\n") == "https://github.com/octocat/hello")
        #expect(configPage("[remote \"origin\"]\n\turl = \"https://github.com/octocat/hello.git\"\n") == "https://github.com/octocat/hello")
        #expect(configPage("[REMOTE \"origin\"]\n\turl=https://github.com/octocat/hello.git\n") == "https://github.com/octocat/hello")
    }

    @Test func commentsAreIgnored() {
        let text = """
        [remote "origin"]
        \t# url = https://github.com/octocat/commented-out.git
        \t; url = https://github.com/octocat/also-commented-out.git
        \turl = https://github.com/octocat/hello.git # the real one
        """
        #expect(configPage(text) == "https://github.com/octocat/hello")
    }

    @Test func windowsLineEndings() {
        #expect(configPage("[remote \"origin\"]\r\n\turl = https://github.com/octocat/hello.git\r\n") == "https://github.com/octocat/hello")
    }

    @Test func credentialsInTheConfigNeverReachTheAddress() {
        let text = "[remote \"origin\"]\n\turl = https://octocat:hunter2@github.com/octocat/hello.git\n"
        let result = configPage(text)
        #expect(result == "https://github.com/octocat/hello")
        #expect(result?.contains("hunter2") == false)
    }

    // MARK: From files on disk

    @Test func normalRepository() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("project")
        try temp.write("[remote \"origin\"]\n\turl = git@github.com:octocat/hello.git\n", to: "project/.git/config")

        let gitDir = try #require(GitRepositoryService.gitDirectory(forRepoAt: repo))
        #expect(GitRemote.githubURL(forGitDirectory: gitDir)?.absoluteString == "https://github.com/octocat/hello")
    }

    @Test func repositoryWithoutConfigGivesNothing() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("project")
        let gitDir = try #require(GitRepositoryService.gitDirectory(forRepoAt: repo))
        #expect(GitRemote.githubURL(forGitDirectory: gitDir) == nil)
    }

    @Test func worktreeUsesTheMainRepositoryConfig() throws {
        let temp = try TempFolder()
        let mainRepo = try temp.repo("main-repo")
        try temp.write("[remote \"origin\"]\n\turl = https://github.com/octocat/hello.git\n", to: "main-repo/.git/config")
        try temp.write("ref: refs/heads/feature\n", to: "main-repo/.git/worktrees/wt/HEAD")
        try temp.write("../..\n", to: "main-repo/.git/worktrees/wt/commondir")
        let worktree = try temp.folder("wt")
        try temp.write("gitdir: \(mainRepo.path)/.git/worktrees/wt\n", to: "wt/.git")

        let status = GitRepositoryService.status(ofProjectAt: worktree.path)
        #expect(status.head == .branch("feature"))
        #expect(status.githubURL?.absoluteString == "https://github.com/octocat/hello")
    }

    @Test func worktreeWithAnAbsoluteCommondir() throws {
        let temp = try TempFolder()
        let mainRepo = try temp.repo("main-repo")
        try temp.write("[remote \"origin\"]\n\turl = https://github.com/octocat/hello.git\n", to: "main-repo/.git/config")
        try temp.write("ref: refs/heads/feature\n", to: "main-repo/.git/worktrees/wt/HEAD")
        try temp.write("\(mainRepo.path)/.git\n", to: "main-repo/.git/worktrees/wt/commondir")
        let worktree = try temp.folder("wt")
        try temp.write("gitdir: \(mainRepo.path)/.git/worktrees/wt\n", to: "wt/.git")

        #expect(GitRepositoryService.status(ofProjectAt: worktree.path).githubURL?.absoluteString == "https://github.com/octocat/hello")
    }

    @Test func submoduleUsesItsOwnConfig() throws {
        let temp = try TempFolder()
        try temp.repo("parent")
        try temp.write("[remote \"origin\"]\n\turl = https://github.com/octocat/parent.git\n", to: "parent/.git/config")
        try temp.write("ref: refs/heads/dev\n", to: "parent/.git/modules/sub/HEAD")
        try temp.write("[remote \"origin\"]\n\turl = https://github.com/octocat/the-submodule.git\n", to: "parent/.git/modules/sub/config")
        let submodule = try temp.folder("parent/sub")
        try temp.write("gitdir: ../.git/modules/sub\n", to: "parent/sub/.git")

        #expect(GitRepositoryService.status(ofProjectAt: submodule.path).githubURL?.absoluteString == "https://github.com/octocat/the-submodule")
    }

    @Test func statusCarriesTheGitHubPage() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("project")
        try temp.write("[remote \"origin\"]\n\turl = git@github.com:octocat/hello.git\n", to: "project/.git/config")
        #expect(GitRepositoryService.status(ofProjectAt: repo.path).githubURL?.absoluteString == "https://github.com/octocat/hello")
    }

    @Test func statusWithoutARemoteHasNoGitHubPage() throws {
        let temp = try TempFolder()
        let repo = try temp.repo("project")
        #expect(GitRepositoryService.status(ofProjectAt: repo.path).githubURL == nil)
        #expect(GitRepositoryService.status(ofProjectAt: "/definitely/not/here").githubURL == nil)
    }
}
