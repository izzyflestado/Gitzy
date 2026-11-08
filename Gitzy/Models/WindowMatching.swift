import Foundation

/// A Finder window and the folder it is showing.
nonisolated struct FinderWindowInfo: Equatable, Sendable {
    let id: Int
    let path: String
}

/// One tab of an Apple Terminal window, and the terminal device it runs on (for example "/dev/ttys003").
nonisolated struct TerminalTabInfo: Equatable, Sendable {
    let windowID: Int
    let tty: String

    /// The device without "/dev/", which is how `ps` writes it.
    var ttyName: String {
        tty.hasPrefix("/dev/") ? String(tty.dropFirst(5)) : tty
    }
}

/// Reading what Finder, Terminal, `ps` and `lsof` say, and deciding which window already belongs to a folder.
/// No system calls happen here, so all of it can be tested with plain text.
///
/// Folders are compared as plain paths. The callers resolve symlinks first (`GitRepositoryService.resolvedPath`),
/// so two routes to the same folder match.
nonisolated enum WindowMatching {

    /// The path without a trailing slash (Finder writes folders as "/Users/me/repo/").
    static func normalized(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }

    /// True when `path` is the folder itself, or somewhere inside it.
    /// "/Users/me/repo-two" is not inside "/Users/me/repo".
    static func isSameOrInside(_ path: String, folder: String) -> Bool {
        let path = normalized(path)
        let folder = normalized(folder)
        if path == folder { return true }
        let prefix = folder == "/" ? "/" : folder + "/"
        return path.hasPrefix(prefix)
    }

    // MARK: Scripts

    /// Lines the scripts write when something they asked for failed: "ERR<tab><message>".
    /// They are skipped when reading windows and tabs, and collected here so they can be reported.
    static func scriptErrors(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, parts[0] == "ERR" else { return nil }
            return String(parts[1])
        }
    }

    // MARK: Finder

    /// Finder's answer: one window per line, "<id><tab><folder>". Lines that do not fit are ignored.
    static func parseFinderWindows(_ text: String) -> [FinderWindowInfo] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let id = Int(parts[0]), let path = folderPath(from: String(parts[1])) else { return nil }
            return FinderWindowInfo(id: id, path: path)
        }
    }

    /// A folder as Finder writes it: a plain path ("/Users/me/repo/") or an address ("file:///Users/me/My%20Repo/").
    static func folderPath(from text: String) -> String? {
        if text.hasPrefix("file://") {
            guard let path = URL(string: text)?.path, path.hasPrefix("/") else { return nil }
            return path
        }
        return text.hasPrefix("/") ? text : nil
    }

    /// The first window showing exactly this folder. A window showing a folder inside it, or above it, does not count.
    static func finderWindow(showing folder: String, in windows: [FinderWindowInfo]) -> FinderWindowInfo? {
        let folder = normalized(folder)
        return windows.first { normalized($0.path) == folder }
    }

    // MARK: Terminal

    /// Terminal's answer: one tab per line, "<window id><tab><tty>".
    static func parseTerminalTabs(_ text: String) -> [TerminalTabInfo] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let id = Int(parts[0]), !parts[1].isEmpty else { return nil }
            return TerminalTabInfo(windowID: id, tty: String(parts[1]))
        }
    }

    /// From `ps -ax -o pid= -o tty= -o stat=`: the processes in front on each of the given terminals.
    /// "In front" is what `ps` marks with a "+" in the status. For an idle prompt that is the shell; while a program
    /// runs, it is that program.
    static func foregroundProcesses(psOutput: String, ttys: Set<String>) -> [String: [Int]] {
        var result: [String: [Int]] = [:]
        for line in psOutput.split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 3, let pid = Int(fields[0]) else { continue }
            let tty = String(fields[1])
            guard ttys.contains(tty), fields[2].contains("+") else { continue }
            result[tty, default: []].append(pid)
        }
        return result
    }

    /// From `lsof -a -d cwd -Fn -p ...`: "p<pid>" starts a process, "n<path>" is its working folder.
    static func parseWorkingDirectories(lsofOutput: String) -> [Int: String] {
        var result: [Int: String] = [:]
        var current: Int?
        for line in lsofOutput.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("p"), let pid = Int(line.dropFirst()) {
                current = pid
            } else if line.hasPrefix("n"), let pid = current {
                result[pid] = String(line.dropFirst())
            }
        }
        return result
    }

    /// The tab to show for a folder: the first one that is working in exactly that folder, otherwise the first one
    /// working somewhere inside it. Tabs are given front window first.
    static func terminalTab(
        inOrUnder folder: String,
        tabs: [TerminalTabInfo],
        pidsByTTY: [String: [Int]],
        directories: [Int: String]
    ) -> TerminalTabInfo? {
        let folder = normalized(folder)
        var inside: TerminalTabInfo?
        for tab in tabs {
            let paths = (pidsByTTY[tab.ttyName] ?? []).compactMap { directories[$0] }
            if paths.contains(where: { normalized($0) == folder }) { return tab }
            if inside == nil, paths.contains(where: { isSameOrInside($0, folder: folder) }) { inside = tab }
        }
        return inside
    }
}
