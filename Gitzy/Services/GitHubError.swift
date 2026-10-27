import Foundation

/// Everything that can go wrong talking to GitHub, with plain-language text for the UI.
/// Messages never contain the token or any request header.
nonisolated enum GitHubError: Error, Equatable, Sendable {
    case noToken
    case invalidToken
    case insufficientScope
    case offline
    case timedOut
    case network
    case rateLimited(retryAfter: Date?)
    case server(status: Int)
    case graphQL(String)
    case unexpectedResponse

    var message: String {
        switch self {
        case .noToken:
            return "No token found in the Keychain. Paste a token to connect."
        case .invalidToken:
            return "GitHub rejected the token. It may be expired or revoked. Use Replace token."
        case .insufficientScope:
            return "The token is missing the read:user permission."
        case .offline:
            return "You appear to be offline."
        case .timedOut:
            return "GitHub took too long to answer."
        case .network:
            return "The network request failed."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "GitHub rate limit reached. Waiting until \(retryAfter.formatted(date: .omitted, time: .shortened))."
            }
            return "GitHub rate limit reached. Try again later."
        case .server(let status):
            return status >= 500
                ? "GitHub is having problems (HTTP \(status)). Try again later."
                : "GitHub refused the request (HTTP \(status))."
        case .graphQL(let text):
            return "GitHub reported a problem: \(text)"
        case .unexpectedResponse:
            return "GitHub sent a reply Gitzy could not read."
        }
    }

    /// Maps an HTTP reply to an error, or nil when the reply was successful.
    /// GitHub signals rate limits with 403 or 429 plus headers; when no header says how long to wait,
    /// its guidance is to wait at least a minute.
    static func classify(
        status: Int,
        retryAfter: String?,
        rateLimitRemaining: String?,
        rateLimitReset: String?,
        bodyMentionsRateLimit: Bool = false,
        now: Date = Date()
    ) -> GitHubError? {
        switch status {
        case 200..<300:
            return nil
        case 401:
            return .invalidToken
        case 403, 429:
            if let seconds = retryAfter.flatMap({ Double($0) }) {
                return .rateLimited(retryAfter: now.addingTimeInterval(seconds))
            }
            if rateLimitRemaining == "0", let reset = rateLimitReset.flatMap({ Double($0) }) {
                return .rateLimited(retryAfter: Date(timeIntervalSince1970: reset))
            }
            if status == 429 || bodyMentionsRateLimit {
                return .rateLimited(retryAfter: now.addingTimeInterval(60))
            }
            return .server(status: status)
        default:
            return .server(status: status)
        }
    }

    static func from(urlError error: URLError) -> GitHubError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .cannotFindHost, .cannotConnectToHost, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return .timedOut
        default:
            return .network
        }
    }

    /// Errors GitHub reports inside a 200 reply. The primary hourly limit arrives this way,
    /// so an exhausted quota (`rateLimitExhausted`) counts as a rate limit whatever the error says.
    static func from(
        graphQLErrors errors: [(type: String?, message: String)],
        rateLimitExhausted: Bool,
        retryAfter: Date?
    ) -> GitHubError {
        guard let first = errors.first else { return .unexpectedResponse }
        if rateLimitExhausted || first.type == "RATE_LIMITED" || first.message.lowercased().contains("rate limit") {
            return .rateLimited(retryAfter: retryAfter)
        }
        if first.type == "INSUFFICIENT_SCOPES" { return .insufficientScope }
        return .graphQL(first.message)
    }
}
