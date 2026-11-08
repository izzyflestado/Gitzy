import AppKit

/// How an attempt to show a folder in Finder or Terminal went.
enum WindowOutcome {
    /// A window now shows the folder. Nothing more to do.
    case done
    /// Nothing was shown. The caller opens the folder the usual way (which makes a new window).
    /// `reason` is something the person should be told (a permission, a timeout), or nil when nothing went wrong.
    case openNormally(reason: String?)
}

/// Asks an app to do something with an AppleScript. NSAppleScript must run on the main thread, so this is MainActor.
private enum AppleScriptRunner {
    enum Result {
        case value(String)
        case failure(String)
    }

    static func run(_ source: String, appName: String) -> Result {
        var errorInfo: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        if let errorInfo {
            return .failure(describe(errorInfo, appName: appName))
        }
        return .value(result?.stringValue ?? "")
    }

    /// An AppleScript string literal: backslashes and quotes escaped.
    static func quoted(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"" + escaped + "\""
    }

    private static func describe(_ info: NSDictionary, appName: String) -> String {
        let number = info.object(forKey: "NSAppleScriptErrorNumber") as? Int
        switch number {
        case -1743: return "macOS has not allowed Gitzy to control \(appName). Allow it in System Settings, Privacy & Security, Automation."
        case -1712: return "\(appName) took too long to answer."
        default:
            let message = info.object(forKey: "NSAppleScriptErrorMessage") as? String
            let detail = [number.map { "error \($0)" }, message].compactMap { $0 }.joined(separator: ": ")
            return "\(appName) would not show its window\(detail.isEmpty ? "" : " (\(detail))")."
        }
    }
}

/// "~/dev/gitzy" rather than "/Users/me/dev/gitzy", for the notes shown in Settings.
private func shortPath(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}

// MARK: - Finder

/// Opens a folder in Finder, either always in a new window or by bringing forward a window that already shows it.
/// Finder is always running, so asking it never launches anything.
///
/// Every attempt leaves a one-line note (`WindowReport`) that Settings shows, so a fallback is never silent.
enum FinderWindows {
    private static let bundleID = "com.apple.finder"

    static func open(_ folder: URL, mode: WindowMode) -> WindowOutcome {
        var lookupNote: String?   // what the search for an open window found, when there was one

        if mode == .existingWindow {
            switch existingWindow(showing: folder) {
            case .found(let id):
                // The window exists, so a second one is never opened from here. If it cannot be raised above the
                // others, Finder is brought forward and the note says what went wrong.
                if let problem = show(windowID: id) {
                    _ = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.activate()
                    record("Found the window already showing “\(folder.lastPathComponent)” but could not raise it (\(problem)). Finder was brought forward, and no second window was opened.")
                } else {
                    record("Showed the Finder window that was already open.")
                }
                return .done
            case .notShowing(let paths, let problems):
                lookupNote = notShowingNote(windowPaths: paths, problems: problems, folder: folder)
            case .failed(let reason):
                record("\(reason) Opened the folder the usual way.")
                return .openNormally(reason: reason)
            }
        }

        let outcome = newWindow(showing: folder)
        switch outcome {
        case .done:
            record(lookupNote.map { "\($0) Opened a new window." } ?? "Opened a new window.")
        case .openNormally(let reason):
            record("\(reason ?? "Finder would not make a window.") Opened the folder the usual way.")
        }
        return outcome
    }

    private static func record(_ text: String) {
        WindowReport.record(text, forKey: WindowReport.finderKey)
    }

    private static func notShowingNote(windowPaths: [String], problems: [String], folder: URL) -> String {
        let count = windowPaths.count
        var text: String
        if count == 0 {
            text = "No Finder window was readable."
        } else {
            let shown = windowPaths.prefix(3).map { shortPath($0) }.joined(separator: ", ")
            let more = count > 3 ? " and more" : ""
            text = "Finder has \(count) window\(count == 1 ? "" : "s") open (\(shown)\(more)), none showing “\(shortPath(folder.path))”."
        }
        if let first = problems.first {
            text += " \(problems.count) could not be read (\(first))."
        }
        return text
    }

    // MARK: Looking

    private enum Lookup {
        case found(Int)
        /// No window shows the folder. `paths` are the folders the windows do show.
        case notShowing(paths: [String], problems: [String])
        case failed(String)
    }

    private static func existingWindow(showing folder: URL) -> Lookup {
        // The tab and line-break characters are made before the `tell`: inside a tell, the app's own words win,
        // and some apps use the word "tab" for something else.
        //
        // The windows are asked for one by one ("Finder window i"), not by looping over a list of them. A list of
        // window references handed back to Finder is what made Finder answer "Unknown object type" for every window.
        // Where a window is comes as an address ("file:///...") and, if that fails, as a path.
        let source = """
        set tabChar to character id 9
        set lineBreak to character id 10
        set foundRows to {}
        tell application id "\(bundleID)"
            with timeout of 3 seconds
                set windowCount to count of Finder windows
                repeat with i from 1 to windowCount
                    try
                        set winID to (id of Finder window i) as text
                        set folderText to ""
                        set problems to ""
                        try
                            set folderText to URL of (target of Finder window i)
                        on error firstError
                            set problems to "address: " & firstError
                        end try
                        if folderText is "" then
                            try
                                set folderText to POSIX path of ((target of Finder window i) as alias)
                            on error secondError
                                set problems to problems & " / path: " & secondError
                            end try
                        end if
                        if folderText is "" then
                            set end of foundRows to "ERR" & tabChar & problems
                        else
                            set end of foundRows to winID & tabChar & folderText
                        end if
                    on error errMsg
                        set end of foundRows to "ERR" & tabChar & errMsg
                    end try
                end repeat
            end timeout
        end tell
        set AppleScript's text item delimiters to lineBreak
        return foundRows as text
        """
        switch AppleScriptRunner.run(source, appName: "Finder") {
        case .failure(let reason):
            return .failed(reason)
        case .value(let text):
            // Finder says where a window is by the route it was opened with. Resolve both sides so symlinks match.
            let windows = WindowMatching.parseFinderWindows(text).map {
                FinderWindowInfo(id: $0.id, path: GitRepositoryService.resolvedPath(of: URL(fileURLWithPath: $0.path)))
            }
            let wanted = GitRepositoryService.resolvedPath(of: folder)

            // Same path first. Then the same folder by identity, which also covers spellings that differ only in
            // capitals, accents or a firmlink.
            if let match = WindowMatching.finderWindow(showing: wanted, in: windows)
                ?? windows.first(where: { sameFolder(URL(fileURLWithPath: $0.path), folder) }) {
                return .found(match.id)
            }
            return .notShowing(paths: windows.map(\.path), problems: WindowMatching.scriptErrors(in: text))
        }
    }

    /// True when both URLs are the very same folder on disk.
    private static func sameFolder(_ a: URL, _ b: URL) -> Bool {
        guard let x = try? a.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let y = try? b.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier else {
            return false
        }
        return x.isEqual(y)
    }

    // MARK: Showing

    /// Raises the window above Finder's others and brings Finder forward. Nil when that worked, otherwise what went wrong.
    private static func show(windowID: Int) -> String? {
        let source = """
        set problem to ""
        tell application id "\(bundleID)"
            with timeout of 3 seconds
                try
                    set w to (first Finder window whose id is \(windowID))
                    try
                        set collapsed of w to false
                    end try
                    set index of w to 1
                on error errMsg
                    set problem to errMsg
                end try
            end timeout
            activate
        end tell
        return problem
        """
        switch AppleScriptRunner.run(source, appName: "Finder") {
        case .failure(let reason): return reason
        case .value(let text): return text.isEmpty ? nil : text
        }
    }

    private static func newWindow(showing folder: URL) -> WindowOutcome {
        let source = """
        tell application id "\(bundleID)"
            with timeout of 3 seconds
                make new Finder window to (POSIX file \(AppleScriptRunner.quoted(folder.path)) as alias)
                activate
            end timeout
        end tell
        """
        switch AppleScriptRunner.run(source, appName: "Finder") {
        case .value: return .done
        case .failure(let reason): return .openNormally(reason: reason)
        }
    }
}

// MARK: - Terminal

/// What the search of Terminal's tabs found.
nonisolated struct TerminalLookup: Sendable {
    /// The tab to show, if one is working in the folder.
    var tab: TerminalTabInfo?
    /// How many programs `ps` showed in front on Terminal's tabs, and the folders they are in.
    var programCount: Int
    var folders: [String]
    /// `ps` itself could not be run.
    var couldNotReadProcesses: Bool
}

/// Brings forward an Apple Terminal window that is already working in a folder.
///
/// Terminal does not say which folder a tab is in, so it is worked out: Terminal says which terminal device each tab
/// uses, `ps` says which programs are in front on those devices, and `lsof` says which folder each one is in.
/// A window is only ever shown. Nothing is typed into it and nothing is run in it.
/// Only Apple's Terminal can be asked about its windows; other terminal apps always get a new window.
///
/// Every attempt leaves a one-line note (`WindowReport`) that Settings shows, so a fallback is never silent.
enum TerminalWindows {
    static let bundleID = "com.apple.Terminal"

    static func isAppleTerminal(_ app: URL) -> Bool {
        Bundle(url: app)?.bundleIdentifier == bundleID
    }

    /// Shows the window that is working in `folder` (or in a folder inside it), if there is one.
    static func showWindow(workingIn folder: URL) async -> WindowOutcome {
        // Telling a closed app something would launch it. If it is closed, the normal way opens it with a new window.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            record("Terminal was not running, so it was opened with a new window.")
            return .openNormally(reason: nil)
        }

        // The tab and line-break characters are made before the `tell`, because inside it "tab" means Terminal's
        // own tab class and not the tab character.
        let listSource = """
        set tabChar to character id 9
        set lineBreak to character id 10
        set foundRows to {}
        tell application id "\(bundleID)"
            with timeout of 3 seconds
                repeat with w in windows
                    try
                        set windowID to (id of w) as text
                        repeat with t in tabs of w
                            try
                                set end of foundRows to windowID & tabChar & (tty of t)
                            on error errMsg
                                set end of foundRows to "ERR" & tabChar & errMsg
                            end try
                        end repeat
                    on error errMsg
                        set end of foundRows to "ERR" & tabChar & errMsg
                    end try
                end repeat
            end timeout
        end tell
        set AppleScript's text item delimiters to lineBreak
        return foundRows as text
        """
        let text: String
        switch AppleScriptRunner.run(listSource, appName: "Terminal") {
        case .failure(let reason):
            record("\(reason) Opened a new window the usual way.")
            return .openNormally(reason: reason)
        case .value(let value):
            text = value
        }

        let tabs = WindowMatching.parseTerminalTabs(text)
        guard !tabs.isEmpty else {
            let detail = WindowMatching.scriptErrors(in: text).first.map { " (\($0))" } ?? ""
            record("Terminal listed no tabs\(detail). Opened a new window.")
            return .openNormally(reason: nil)
        }

        // Reading what is running can take a moment, so it is done off the main thread.
        let ttys = Set(tabs.map(\.ttyName))
        let wanted = GitRepositoryService.resolvedPath(of: folder)
        let lookup = await Task.detached { () -> TerminalLookup in
            guard let snapshot = TerminalProcesses.snapshot(ttys: ttys) else {
                return TerminalLookup(tab: nil, programCount: 0, folders: [], couldNotReadProcesses: true)
            }
            let pids = snapshot.pidsByTTY.values.flatMap { $0 }
            let folders = Array(Set(pids.compactMap { snapshot.directories[$0] })).sorted()
            let tab = WindowMatching.terminalTab(
                inOrUnder: wanted,
                tabs: tabs,
                pidsByTTY: snapshot.pidsByTTY,
                directories: snapshot.directories
            )
            return TerminalLookup(tab: tab, programCount: pids.count, folders: folders, couldNotReadProcesses: false)
        }.value

        guard let tab = lookup.tab else {
            record("\(notWorkingNote(lookup, tabCount: tabs.count, folder: folder)) Opened a new window.")
            return .openNormally(reason: nil)
        }

        let outcome = show(tab)
        switch outcome {
        case .done:
            record("Showed the Terminal window that was already working in “\(folder.lastPathComponent)”.")
        case .openNormally(let reason):
            record("\(reason ?? "Terminal would not show its window.") Opened a new window the usual way.")
        }
        return outcome
    }

    private static func record(_ text: String) {
        WindowReport.record(text, forKey: WindowReport.terminalKey)
    }

    private static func notWorkingNote(_ lookup: TerminalLookup, tabCount: Int, folder: URL) -> String {
        let tabs = "\(tabCount) tab\(tabCount == 1 ? "" : "s")"
        if lookup.couldNotReadProcesses {
            return "Terminal has \(tabs), but the list of running programs could not be read."
        }
        if lookup.programCount == 0 {
            return "Terminal has \(tabs), but no program was found running in front in them."
        }
        if lookup.folders.isEmpty {
            return "Terminal has \(tabs) with \(lookup.programCount) program\(lookup.programCount == 1 ? "" : "s") in front, but their folders could not be read."
        }
        let shown = lookup.folders.prefix(3).map { shortPath($0) }.joined(separator: ", ")
        let more = lookup.folders.count > 3 ? " and more" : ""
        return "Terminal has \(tabs), working in \(shown)\(more). None is in “\(folder.lastPathComponent)” or below it."
    }

    private static func show(_ tab: TerminalTabInfo) -> WindowOutcome {
        let source = """
        tell application id "\(bundleID)"
            with timeout of 3 seconds
                set w to (first window whose id is \(tab.windowID))
                try
                    set miniaturized of w to false
                end try
                try
                    set selected tab of w to (first tab of w whose tty is \(AppleScriptRunner.quoted(tab.tty)))
                end try
                set index of w to 1
                activate
            end timeout
        end tell
        """
        switch AppleScriptRunner.run(source, appName: "Terminal") {
        case .value: return .done
        case .failure(let reason): return .openNormally(reason: reason)
        }
    }
}
