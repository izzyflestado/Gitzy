import Foundation

/// Finds a project's GitHub page from the remote address in its `.git/config`.
/// Like the rest of the Git reading in Gitzy it only reads files: no git process, nothing written, no network.
///
/// The address that comes back is never the one found in the file. It is built again from the owner and repository
/// name alone (`https://github.com/<owner>/<repository>`), after both were checked. A remote written with a password
/// or token in it (`https://name:token@github.com/...`) therefore gives a clean page address, and the credentials
/// are not kept, shown or passed to the browser.
nonisolated enum GitRemote {

    /// A config file is a few hundred bytes. Anything past this is not read.
    private static let configLimit = 262_144

    /// The hosts that mean github.com. `ssh.github.com` is GitHub's own SSH-over-port-443 address.
    private static let hosts: Set<String> = ["github.com", "www.github.com", "ssh.github.com"]

    // MARK: From a repository

    /// The GitHub page for the repository whose Git directory this is (what `GitRepositoryService.gitDirectory` returns).
    /// Nil when there is no config, no remote, or no remote on GitHub.
    static func githubURL(forGitDirectory gitDir: URL) -> URL? {
        let config = configDirectory(forGitDirectory: gitDir).appendingPathComponent("config")
        guard let text = readText(at: config, limit: configLimit) else { return nil }
        return githubURL(fromConfig: text)
    }

    /// Where this repository's `config` lives.
    /// A normal repository and a submodule keep it in their own Git directory.
    /// A linked worktree shares the main repository's config, and a `commondir` file says where that is.
    private static func configDirectory(forGitDirectory gitDir: URL) -> URL {
        // Marked as a directory, otherwise a relative pointer would resolve one level too high.
        let gitDir = URL(fileURLWithPath: gitDir.path, isDirectory: true)
        guard let text = readText(at: gitDir.appendingPathComponent("commondir"), limit: 4096) else { return gitDir }
        let pointer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pointer.isEmpty else { return gitDir }
        // An absolute path ignores `gitDir`; a relative one (normally "../..") is resolved against it.
        return URL(fileURLWithPath: pointer, isDirectory: true, relativeTo: gitDir).standardizedFileURL
    }

    private static func readText(at file: URL, limit: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: From the config text

    /// `origin` when it is on GitHub, otherwise the first other remote that is.
    static func githubURL(fromConfig text: String) -> URL? {
        var remote: String?     // the remote whose [remote "..."] section the current line is in
        var fallback: URL?      // the first GitHub remote that is not called origin

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                remote = remoteName(inHeader: line)
            } else if let name = remote,
                      let address = value(ofKey: "url", inLine: line),
                      let url = githubURL(fromRemote: address) {
                if name == "origin" { return url }
                if fallback == nil { fallback = url }
            }
        }
        return fallback
    }

    /// `[remote "origin"]` gives "origin". Any other kind of section gives nil.
    private static func remoteName(inHeader line: String) -> String? {
        guard let close = line.firstIndex(of: "]") else { return nil }
        let inside = line[line.index(after: line.startIndex)..<close].trimmingCharacters(in: .whitespaces)
        let pieces = inside.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard pieces.count == 2, pieces[0].lowercased() == "remote" else { return nil }
        let quoted = pieces[1].trimmingCharacters(in: .whitespaces)
        guard quoted.count >= 2, quoted.hasPrefix("\""), quoted.hasSuffix("\"") else { return nil }
        return String(quoted.dropFirst().dropLast())
    }

    /// The value of `key = value` when the line is that key (keys are not case sensitive). Comments are ignored.
    private static func value(ofKey key: String, inLine line: String) -> String? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        guard line[..<equals].trimmingCharacters(in: .whitespaces).lowercased() == key else { return nil }

        var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        } else if let comment = value.range(of: #"\s[#;]"#, options: .regularExpression) {
            value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        return value.isEmpty ? nil : value
    }

    // MARK: From one remote address

    /// The GitHub page for one remote address, or nil when it is not a GitHub repository.
    ///
    /// Understood: `https://github.com/owner/repo(.git)`, `http://`, `git://`, `ssh://git@github.com(:port)/owner/repo`
    /// and the short form `git@github.com:owner/repo(.git)`. A user name, password or token in front of the host is dropped.
    /// A local path, another host, a GitHub Enterprise server, or an owner or repository name with unusual
    /// characters gives nil.
    static func githubURL(fromRemote remote: String) -> URL? {
        let value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String

        if let schemeEnd = value.range(of: "://") {
            let scheme = value[..<schemeEnd.lowerBound].lowercased()
            guard ["https", "http", "ssh", "git"].contains(scheme) else { return nil }
            let rest = value[schemeEnd.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            guard isGitHub(authority: String(rest[..<slash]), allowsPort: true) else { return nil }
            path = String(rest[rest.index(after: slash)...])
        } else {
            // The short form: [user@]github.com:owner/repo
            guard let colon = value.firstIndex(of: ":") else { return nil }
            guard isGitHub(authority: String(value[..<colon]), allowsPort: false) else { return nil }
            path = String(value[value.index(after: colon)...])
        }
        return repositoryURL(fromPath: path)
    }

    /// True when the part before the first slash is github.com, once any `user:password@` and `:port` are taken off.
    private static func isGitHub(authority: String, allowsPort: Bool) -> Bool {
        var host = Substring(authority)
        if let at = host.lastIndex(of: "@") { host = host[host.index(after: at)...] }
        if allowsPort, let colon = host.firstIndex(of: ":") { host = host[..<colon] }
        return hosts.contains(host.lowercased())
    }

    /// `owner/repo` or `owner/repo.git` (a trailing slash is fine) becomes the page address. Anything else gives nil.
    private static func repositoryURL(fromPath path: String) -> URL? {
        let cleaned = path.prefix(while: { $0 != "?" && $0 != "#" })
        let parts = cleaned.split(separator: "/")   // empty pieces are skipped, so a trailing slash does no harm
        guard parts.count == 2 else { return nil }

        let owner = String(parts[0])
        var repository = String(parts[1])
        if repository.lowercased().hasSuffix(".git") { repository = String(repository.dropLast(4)) }

        guard isValidOwner(owner), isValidRepository(repository) else { return nil }
        return URL(string: "https://github.com/\(owner)/\(repository)")
    }

    /// Same characters the profile button accepts: plain ASCII letters, digits, `-` and `_`.
    private static func isValidOwner(_ name: String) -> Bool {
        (1...64).contains(name.count)
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// GitHub repository names: ASCII letters, digits, `-`, `_` and `.`, and never just "." or "..".
    private static func isValidRepository(_ name: String) -> Bool {
        (1...100).contains(name.count)
            && name != "." && name != ".."
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == ".") }
    }
}
