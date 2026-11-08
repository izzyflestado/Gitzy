import Foundation

/// What is running in front on some terminal devices, and which folder each of those programs is in.
nonisolated struct TerminalSnapshot: Sendable {
    /// Terminal device name (for example "ttys003") to the programs in front on it.
    var pidsByTTY: [String: [Int]]
    /// Program id to the folder it is working in.
    var directories: [Int: String]
}

/// Reads the process list with `ps` and working folders with `lsof`. Both are read-only, are started directly (no
/// shell) with fixed arguments, and only ever look at the person's own programs. Call this off the main thread.
nonisolated enum TerminalProcesses {

    /// Nil when `ps` could not be run at all. When `lsof` fails, the snapshot has no folders, so nothing matches.
    static func snapshot(ttys: Set<String>) -> TerminalSnapshot? {
        guard let ps = run("/bin/ps", ["-ax", "-o", "pid=", "-o", "tty=", "-o", "stat="]) else { return nil }
        let pidsByTTY = WindowMatching.foregroundProcesses(psOutput: ps, ttys: ttys)
        let pids = pidsByTTY.values.flatMap { $0 }
        guard !pids.isEmpty else { return TerminalSnapshot(pidsByTTY: [:], directories: [:]) }

        // lsof exits with 1 when one of the programs has already gone, but still prints the others.
        let list = pids.map(String.init).joined(separator: ",")
        let lsof = run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-Fn", "-p", list]) ?? ""
        return TerminalSnapshot(pidsByTTY: pidsByTTY, directories: WindowMatching.parseWorkingDirectories(lsofOutput: lsof))
    }

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // Read before waiting, so a long answer can never fill the pipe and stall the program.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
