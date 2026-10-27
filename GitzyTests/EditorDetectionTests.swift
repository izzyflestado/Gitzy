import Foundation
import Testing
@testable import Gitzy

nonisolated struct EditorDetectionTests {
    private func path(_ json: String) -> String? {
        VSCodeDetector.lastActivePath(in: Data(json.utf8))
    }

    // MARK: VS Code's storage.json

    @Test func aFolderWindow() {
        let json = #"{"windowsState":{"lastActiveWindow":{"folder":"file:///Users/me/app"}}}"#
        #expect(path(json) == "/Users/me/app")
    }

    @Test func spacesAndOtherCharactersAreDecoded() {
        let json = #"{"windowsState":{"lastActiveWindow":{"folder":"file:///Users/me/My%20App"}}}"#
        #expect(path(json) == "/Users/me/My App")
    }

    @Test func aWorkspaceFileWindow() {
        let json = #"{"windowsState":{"lastActiveWindow":{"workspaceIdentifier":{"id":"abc","configURIPath":"file:///Users/me/app/app.code-workspace"}}}}"#
        #expect(path(json) == "/Users/me/app/app.code-workspace")
    }

    @Test func aRemoteWindowGivesNothing() {
        let json = #"{"windowsState":{"lastActiveWindow":{"folder":"vscode-remote://ssh-remote%2Bhost/home/me/app"}}}"#
        #expect(path(json) == nil)
    }

    @Test func anEmptyWindowGivesNothing() {
        #expect(path(#"{"windowsState":{"lastActiveWindow":{}}}"#) == nil)
        #expect(path(#"{"windowsState":{"openedWindows":[]}}"#) == nil)
    }

    @Test func unreadableFilesGiveNothing() {
        #expect(path("") == nil)
        #expect(path("not json") == nil)
        #expect(path("[]") == nil)
        #expect(path("{}") == nil)
    }

    // MARK: Recognising editors

    @Test func editorsAreRecognisedByBundleID() {
        #expect(CodeEditor(bundleID: "com.apple.dt.Xcode") == .xcode)
        #expect(CodeEditor(bundleID: "com.microsoft.VSCode") == .vscode)
        #expect(CodeEditor(bundleID: "com.apple.Terminal") == nil)
        #expect(CodeEditor(bundleID: "") == nil)
    }
}
