import AppKit

/// The editors Gitzy can ask which project is open.
nonisolated enum CodeEditor: Equatable, Sendable {
    case xcode
    case vscode

    init?(bundleID: String) {
        switch bundleID {
        case "com.apple.dt.Xcode": self = .xcode
        case "com.microsoft.VSCode": self = .vscode
        default: return nil
        }
    }

    var name: String {
        switch self {
        case .xcode: return "Xcode"
        case .vscode: return "VS Code"
        }
    }
}

/// What asking an editor about its open project came back with.
nonisolated enum Detection: Equatable, Sendable {
    /// A file or folder inside the open project, with symlinks resolved.
    case found(String)
    /// Why there was no answer, in plain language.
    case unavailable(String)
}

/// Asks Xcode which project is open. Runs only when Xcode has just come to the front (or the widget is switched on),
/// and never launches Xcode. NSAppleScript must run on the main thread, so this type is MainActor on purpose.
enum XcodeDetector {
    static let bundleID = "com.apple.dt.Xcode"

    /// Two ways of asking, tried in order. If Xcode's scripting dictionary lacks the first, the second still works.
    private static let expressions = [
        "path of active workspace document",
        "path of document 1",
    ]

    static func activeDocument() -> Detection {
        // Telling a closed app something would launch it, so check first.
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty else {
            return .unavailable("Xcode is not running.")
        }

        var problem = "Xcode did not say which project is open."
        for expression in expressions {
            let source = """
            tell application id "\(bundleID)"
                with timeout of 2 seconds
                    return \(expression)
                end timeout
            end tell
            """
            var errorInfo: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
            if let path = result?.stringValue, path.hasPrefix("/") {
                return .found(GitRepositoryService.resolvedPath(of: URL(fileURLWithPath: path)))
            }
            guard let errorInfo else { continue }
            let number = errorInfo.object(forKey: "NSAppleScriptErrorNumber") as? Int
            problem = describe(errorNumber: number)
            if number == -1743 || number == -1712 { break }   // asking again would fail the same way
        }
        return .unavailable(problem)
    }

    private static func describe(errorNumber: Int?) -> String {
        guard let number = errorNumber else { return "Xcode did not say which project is open." }
        switch number {
        case -1743: return "macOS has not allowed Gitzy to control Xcode. Allow it in System Settings, Privacy & Security, Automation."
        case -1712: return "Xcode took too long to answer."
        case -1728: return "Xcode has no project open."
        default: return "Xcode refused the question (error \(number))."
        }
    }
}

/// Reads which folder VS Code last had in front from its own storage.json. Read-only.
/// VS Code decides when it writes that file, so this can lag behind what is on screen.
nonisolated enum VSCodeDetector {
    static func storageFile() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Code/User/globalStorage/storage.json")
    }

    static func lastActiveFolder() -> Detection {
        guard let data = try? Data(contentsOf: storageFile()) else {
            return .unavailable("Could not read VS Code's storage.json.")
        }
        guard let path = lastActivePath(in: data) else {
            return .unavailable("VS Code's last active window has no local folder open.")
        }
        return .found(GitRepositoryService.resolvedPath(of: URL(fileURLWithPath: path)))
    }

    /// The folder (or .code-workspace file) of the last active window, as a plain path. Remote windows give nil.
    static func lastActivePath(in data: Data) -> String? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let state = root["windowsState"] as? [String: Any],
              let window = state["lastActiveWindow"] as? [String: Any] else { return nil }

        if let folder = window["folder"] as? String, let path = filePath(fromURI: folder) {
            return path
        }
        if let workspace = window["workspaceIdentifier"] as? [String: Any],
           let config = workspace["configURIPath"] as? String,
           let path = filePath(fromURI: config) {
            return path
        }
        return nil
    }

    private static func filePath(fromURI text: String) -> String? {
        guard let url = URL(string: text), url.isFileURL else { return nil }
        return url.path
    }
}
