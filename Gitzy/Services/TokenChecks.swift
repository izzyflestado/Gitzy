import Foundation

/// Cheap checks on what the person pastes, done before anything is sent anywhere.
nonisolated enum TokenFormat {
    /// The pasted text without surrounding spaces or line breaks, or nil when it cannot be a GitHub token.
    /// GitHub tokens are made of letters, digits and underscores (a few kinds also use hyphens).
    /// Refusing everything else also keeps stray control characters out of the request header.
    static func cleaned(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (20...255).contains(trimmed.count) else { return nil }
        let allowed = trimmed.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (
                (scalar.value >= 48 && scalar.value <= 57)      // 0-9
                || (scalar.value >= 65 && scalar.value <= 90)   // A-Z
                || (scalar.value >= 97 && scalar.value <= 122)  // a-z
                || scalar == "_" || scalar == "-"
            )
        }
        return allowed ? trimmed : nil
    }
}

/// What GitHub says a classic token is allowed to do, compared with what Gitzy needs: only `read:user`.
nonisolated struct ScopeReport: Equatable, Sendable {
    /// False when GitHub did not list any scopes (fine-grained tokens, for example).
    let known: Bool
    let hasReadUser: Bool
    /// Everything beyond read:user. The broader `user` scope counts here too.
    let extras: [String]

    init(scopes: [String]?) {
        guard let scopes else {
            known = false
            hasReadUser = false
            extras = []
            return
        }
        known = true
        hasReadUser = scopes.contains("read:user") || scopes.contains("user")
        extras = scopes.filter { $0 != "read:user" }
    }

    /// A sentence for the Settings screen, or nil when the token is exactly right.
    var warning: String? {
        if !known {
            return "GitHub did not report this token's permissions, so Gitzy cannot confirm it has read:user."
        }
        let list = extras.joined(separator: ", ")
        switch (hasReadUser, extras.isEmpty) {
        case (true, true):
            return nil
        case (true, false):
            return "This token can do more than Gitzy needs (\(list)). Consider replacing it with a token that has only read:user."
        case (false, true):
            return "This token does not have read:user, so private contributions will not be counted."
        case (false, false):
            return "This token does not have read:user and has other permissions (\(list)). Replace it with a token that has only read:user."
        }
    }
}
