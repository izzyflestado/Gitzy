import Foundation
import Testing
@testable import Gitzy

nonisolated struct IDETargetTests {

    private func name(_ url: URL) -> String { url.lastPathComponent }

    @Test func xcodeGetsTheWorkspace() throws {
        let temp = try TempFolder()
        let repo = try temp.folder("repo")
        try temp.folder("repo/App.xcworkspace")
        #expect(name(IDETarget.target(forFolder: repo, isXcode: true)) == "App.xcworkspace")
    }

    @Test func workspaceIsPreferredOverProject() throws {
        let temp = try TempFolder()
        let repo = try temp.folder("repo")
        try temp.folder("repo/App.xcodeproj")
        try temp.folder("repo/App.xcworkspace")
        #expect(name(IDETarget.target(forFolder: repo, isXcode: true)) == "App.xcworkspace")
    }

    @Test func xcodeGetsTheProjectWhenThereIsNoWorkspace() throws {
        let temp = try TempFolder()
        let repo = try temp.folder("repo")
        try temp.folder("repo/App.xcodeproj")
        #expect(name(IDETarget.target(forFolder: repo, isXcode: true)) == "App.xcodeproj")
    }

    @Test func theFirstOneByNameIsUsedWhenThereAreSeveral() throws {
        let temp = try TempFolder()
        let repo = try temp.folder("repo")
        try temp.folder("repo/Zed.xcodeproj")
        try temp.folder("repo/Alpha.xcodeproj")
        #expect(name(IDETarget.target(forFolder: repo, isXcode: true)) == "Alpha.xcodeproj")
    }

    @Test func xcodeGetsTheFolderWhenThereIsNoProjectFile() throws {
        let temp = try TempFolder()
        let repo = try temp.folder("repo")
        try temp.write("// swift-tools-version: 6.0\n", to: "repo/Package.swift")
        #expect(IDETarget.target(forFolder: repo, isXcode: true) == repo)
    }

    @Test func projectFilesDeeperDownAreNotSearched() throws {
        let temp = try TempFolder()
        let repo = try temp.folder("repo")
        try temp.folder("repo/Pods/Pods.xcodeproj")
        #expect(IDETarget.target(forFolder: repo, isXcode: true) == repo)
    }

    @Test func otherEditorsAlwaysGetTheFolder() throws {
        let temp = try TempFolder()
        let repo = try temp.folder("repo")
        try temp.folder("repo/App.xcworkspace")
        #expect(IDETarget.target(forFolder: repo, isXcode: false) == repo)
    }

    @Test func aMissingFolderGivesTheFolderBack() {
        let gone = URL(fileURLWithPath: "/definitely/not/here", isDirectory: true)
        #expect(IDETarget.target(forFolder: gone, isXcode: true) == gone)
    }

    // MARK: Automatic choice

    @Test func xcodeProjectsOpenInXcodeFirst() throws {
        let temp = try TempFolder()
        let repo = try temp.folder("repo")
        try temp.folder("repo/App.xcodeproj")
        #expect(IDETarget.isXcodeProject(repo))
        #expect(IDETarget.automaticOrder(forFolder: repo) == [IDETarget.xcodeBundleID, IDETarget.vscodeBundleID])
    }

    @Test func aWorkspaceAloneCountsAsAnXcodeProject() throws {
        let temp = try TempFolder()
        let repo = try temp.folder("repo")
        try temp.folder("repo/App.xcworkspace")
        #expect(IDETarget.isXcodeProject(repo))
    }

    @Test func swiftPackagesOpenInXcodeFirst() throws {
        let temp = try TempFolder()
        let repo = try temp.folder("repo")
        try temp.write("// swift-tools-version: 6.0\n", to: "repo/Package.swift")
        #expect(IDETarget.automaticOrder(forFolder: repo) == [IDETarget.xcodeBundleID, IDETarget.vscodeBundleID])
    }

    @Test func everythingElseOpensInVSCodeFirst() throws {
        let temp = try TempFolder()
        let repo = try temp.folder("repo")
        try temp.write("{}\n", to: "repo/package.json")
        try temp.write("print('hi')\n", to: "repo/main.py")
        #expect(!IDETarget.isXcodeProject(repo))
        #expect(IDETarget.automaticOrder(forFolder: repo) == [IDETarget.vscodeBundleID, IDETarget.xcodeBundleID])
    }

    @Test func anXcodeProjectDeeperDownDoesNotMakeItAnXcodeProject() throws {
        let temp = try TempFolder()
        let repo = try temp.folder("repo")
        try temp.folder("repo/Pods/Pods.xcodeproj")
        try temp.write("{}\n", to: "repo/package.json")
        #expect(!IDETarget.isXcodeProject(repo))
    }

    @Test func aMissingFolderIsNotAnXcodeProject() {
        let gone = URL(fileURLWithPath: "/definitely/not/here", isDirectory: true)
        #expect(!IDETarget.isXcodeProject(gone))
        #expect(IDETarget.automaticOrder(forFolder: gone).first == IDETarget.vscodeBundleID)
    }
}
