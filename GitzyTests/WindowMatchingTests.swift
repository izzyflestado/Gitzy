import Foundation
import Testing
@testable import Gitzy

/// Reading what Finder, Terminal, `ps` and `lsof` say, and choosing the window that belongs to a folder.
nonisolated struct WindowMatchingTests {

    // MARK: Paths

    @Test func trailingSlashesAreIgnored() {
        #expect(WindowMatching.normalized("/Users/me/repo/") == "/Users/me/repo")
        #expect(WindowMatching.normalized("/Users/me/repo") == "/Users/me/repo")
        #expect(WindowMatching.normalized("/") == "/")
    }

    @Test func insideMeansTheFolderItselfOrBelowIt() {
        #expect(WindowMatching.isSameOrInside("/Users/me/repo", folder: "/Users/me/repo"))
        #expect(WindowMatching.isSameOrInside("/Users/me/repo/Sources/App", folder: "/Users/me/repo/"))
        #expect(!WindowMatching.isSameOrInside("/Users/me/repo-two", folder: "/Users/me/repo"))
        #expect(!WindowMatching.isSameOrInside("/Users/me", folder: "/Users/me/repo"))
    }

    // MARK: Finder

    @Test func finderWindowsAreRead() {
        let text = "101\t/Users/me/repo/\n102\t/Users/me/\n\nnot a window\nx\t/nope\n103\trelative/path\n"
        #expect(WindowMatching.parseFinderWindows(text) == [
            FinderWindowInfo(id: 101, path: "/Users/me/repo/"),
            FinderWindowInfo(id: 102, path: "/Users/me/"),
        ])
        #expect(WindowMatching.parseFinderWindows("").isEmpty)
    }

    @Test func finderAddressesAreReadAsPaths() {
        let text = "7\tfile:///Users/me/My%20Repo/\n8\tfile:///Users/me/caf%C3%A9/\n9\tfile://bad\n10\thttp://example.com/\n"
        #expect(WindowMatching.parseFinderWindows(text) == [
            FinderWindowInfo(id: 7, path: "/Users/me/My Repo"),
            FinderWindowInfo(id: 8, path: "/Users/me/café"),
        ])
        #expect(WindowMatching.folderPath(from: "/Users/me/repo/") == "/Users/me/repo/")
        #expect(WindowMatching.folderPath(from: "relative") == nil)
    }

    @Test func finderShowsOnlyAWindowOnExactlyThatFolder() {
        let windows = [
            FinderWindowInfo(id: 1, path: "/Users/me/repo/Sources"),
            FinderWindowInfo(id: 2, path: "/Users/me"),
            FinderWindowInfo(id: 3, path: "/Users/me/repo/"),
            FinderWindowInfo(id: 4, path: "/Users/me/repo"),
        ]
        #expect(WindowMatching.finderWindow(showing: "/Users/me/repo", in: windows)?.id == 3)   // the front-most one
        #expect(WindowMatching.finderWindow(showing: "/Users/me/other", in: windows) == nil)
        #expect(WindowMatching.finderWindow(showing: "/Users/me/repo", in: []) == nil)
    }

    // MARK: Terminal tabs

    @Test func terminalTabsAreRead() {
        let tabs = WindowMatching.parseTerminalTabs("5\t/dev/ttys001\n5\t/dev/ttys002\n\n9\t/dev/ttys007\nbad\n")
        #expect(tabs == [
            TerminalTabInfo(windowID: 5, tty: "/dev/ttys001"),
            TerminalTabInfo(windowID: 5, tty: "/dev/ttys002"),
            TerminalTabInfo(windowID: 9, tty: "/dev/ttys007"),
        ])
        #expect(tabs[0].ttyName == "ttys001")
        #expect(TerminalTabInfo(windowID: 1, tty: "ttys009").ttyName == "ttys009")
    }

    @Test func onlyTheProgramsInFrontOnTheAskedTerminalsAreKept() {
        let ps = """
          101 ttys001 Ss
          102 ttys001 S+
          201 ttys002 Ss+
          301 ??      Ss
          401 ttys009 S+
        """
        let result = WindowMatching.foregroundProcesses(psOutput: ps, ttys: ["ttys001", "ttys002"])
        #expect(result == ["ttys001": [102], "ttys002": [201]])
    }

    @Test func workingFoldersAreRead() {
        let lsof = "p102\nn/Users/me/repo\np201\nn/Users/me/other folder\n"
        #expect(WindowMatching.parseWorkingDirectories(lsofOutput: lsof) == [
            102: "/Users/me/repo",
            201: "/Users/me/other folder",
        ])
        #expect(WindowMatching.parseWorkingDirectories(lsofOutput: "").isEmpty)
    }

    @Test func terminalPrefersAnExactFolderOverOneInsideIt() {
        let tabs = [
            TerminalTabInfo(windowID: 1, tty: "/dev/ttys001"),   // inside the repo
            TerminalTabInfo(windowID: 2, tty: "/dev/ttys002"),   // exactly the repo
            TerminalTabInfo(windowID: 3, tty: "/dev/ttys003"),   // somewhere else
        ]
        let pids = ["ttys001": [11], "ttys002": [22], "ttys003": [33]]
        let folders = [11: "/Users/me/repo/Sources", 22: "/Users/me/repo", 33: "/Users/me/repo-two"]

        let match = WindowMatching.terminalTab(inOrUnder: "/Users/me/repo", tabs: tabs, pidsByTTY: pids, directories: folders)
        #expect(match?.windowID == 2)
    }

    @Test func terminalFallsBackToAFolderInsideTheRepository() {
        let tabs = [
            TerminalTabInfo(windowID: 1, tty: "/dev/ttys001"),
            TerminalTabInfo(windowID: 2, tty: "/dev/ttys002"),
        ]
        let pids = ["ttys001": [11], "ttys002": [22]]
        let folders = [11: "/Users/me/elsewhere", 22: "/Users/me/repo/Sources"]

        let match = WindowMatching.terminalTab(inOrUnder: "/Users/me/repo", tabs: tabs, pidsByTTY: pids, directories: folders)
        #expect(match?.windowID == 2)
    }

    @Test func terminalGivesNothingWhenNoTabIsInTheRepository() {
        let tabs = [TerminalTabInfo(windowID: 1, tty: "/dev/ttys001"), TerminalTabInfo(windowID: 2, tty: "/dev/ttys002")]
        // Tab 2 has no known program, tab 1 is in a sibling folder with the same beginning.
        let pids = ["ttys001": [11]]
        let folders = [11: "/Users/me/repo-two"]

        #expect(WindowMatching.terminalTab(inOrUnder: "/Users/me/repo", tabs: tabs, pidsByTTY: pids, directories: folders) == nil)
        #expect(WindowMatching.terminalTab(inOrUnder: "/Users/me/repo", tabs: [], pidsByTTY: [:], directories: [:]) == nil)
    }

    // MARK: The saved choice

    @Test func theChoiceStartsAsANewWindowAndIsRemembered() throws {
        let name = "WindowModeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(WindowMode.saved(forKey: WindowMode.finderKey, in: defaults) == .newWindow)

        defaults.set(WindowMode.existingWindow.rawValue, forKey: WindowMode.finderKey)
        #expect(WindowMode.saved(forKey: WindowMode.finderKey, in: defaults) == .existingWindow)
        // Finder and Terminal are separate choices.
        #expect(WindowMode.saved(forKey: WindowMode.terminalKey, in: defaults) == .newWindow)
    }

    @Test func anUnreadableChoiceIsANewWindow() throws {
        let name = "WindowModeTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        defaults.set("somethingFromTheFuture", forKey: WindowMode.terminalKey)
        #expect(WindowMode.saved(forKey: WindowMode.terminalKey, in: defaults) == .newWindow)
    }

    // MARK: Script errors and the report

    @Test func scriptErrorLinesAreCollectedAndNeverTakenForWindows() {
        let text = "101\t/Users/me/repo/\nERR\tCan't get target of window 2.\nERR\tCan't make tab into type text.\n"
        #expect(WindowMatching.scriptErrors(in: text) == ["Can't get target of window 2.", "Can't make tab into type text."])
        #expect(WindowMatching.parseFinderWindows(text) == [FinderWindowInfo(id: 101, path: "/Users/me/repo/")])
        #expect(WindowMatching.parseTerminalTabs("ERR\tsomething\n").isEmpty)
        #expect(WindowMatching.scriptErrors(in: "101\t/Users/me/repo/\n").isEmpty)
    }

    @Test func theReportKeepsTheLastLinePerApp() throws {
        let name = "WindowReportTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        WindowReport.record("first", forKey: WindowReport.finderKey, in: defaults)
        WindowReport.record("second", forKey: WindowReport.finderKey, in: defaults)
        WindowReport.record("terminal note", forKey: WindowReport.terminalKey, in: defaults)

        let finderLine = try #require(defaults.string(forKey: WindowReport.finderKey))
        let terminalLine = try #require(defaults.string(forKey: WindowReport.terminalKey))
        #expect(finderLine.hasSuffix("— second"))
        #expect(terminalLine.hasSuffix("— terminal note"))
    }
}
