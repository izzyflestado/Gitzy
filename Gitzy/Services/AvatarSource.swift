import Foundation

/// Decides which addresses Gitzy will download a profile picture from.
///
/// GitHub gives each account's picture as an address on its own picture servers (avatars.githubusercontent.com),
/// not on api.github.com. That is the one place besides api.github.com that Gitzy ever contacts. Only a plain
/// HTTPS address on those servers is accepted, with no user name, password or port, so a changed or odd reply
/// can never make Gitzy contact anywhere else.
nonisolated enum AvatarSource {
    private static let domain = ".githubusercontent.com"
    private static let hostPrefix = "avatars"

    /// The address if it is a profile-picture address, otherwise nil.
    static func validated(_ text: String?) -> URL? {
        guard let text,
              let components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              let host = components.host?.lowercased(),
              isAvatarHost(host)
        else { return nil }
        return components.url
    }

    /// "avatars.githubusercontent.com", and the numbered forms older GitHub replies used ("avatars3...").
    static func isAvatarHost(_ host: String) -> Bool {
        guard host.hasSuffix(domain) else { return false }
        let label = host.dropLast(domain.count)
        guard label.hasPrefix(hostPrefix) else { return false }
        return label.dropFirst(hostPrefix.count).allSatisfy { ("0"..."9").contains($0) }
    }
}
