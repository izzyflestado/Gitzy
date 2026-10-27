import Foundation
import Testing
@testable import Gitzy

nonisolated struct GitHubErrorTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func classify(
        _ status: Int,
        retryAfter: String? = nil,
        remaining: String? = nil,
        reset: String? = nil,
        bodyMentionsRateLimit: Bool = false
    ) -> GitHubError? {
        GitHubError.classify(
            status: status,
            retryAfter: retryAfter,
            rateLimitRemaining: remaining,
            rateLimitReset: reset,
            bodyMentionsRateLimit: bodyMentionsRateLimit,
            now: now
        )
    }

    // MARK: HTTP status

    @Test func successIsNotAnError() {
        #expect(classify(200) == nil)
        #expect(classify(204) == nil)
    }

    @Test func rejectedToken() {
        #expect(classify(401) == .invalidToken)
    }

    @Test func retryAfterHeaderWins() {
        #expect(classify(403, retryAfter: "30") == .rateLimited(retryAfter: now.addingTimeInterval(30)))
        #expect(classify(429, retryAfter: "120", remaining: "0", reset: "1800000000")
                == .rateLimited(retryAfter: now.addingTimeInterval(120)))
    }

    @Test func exhaustedQuotaUsesTheResetTime() {
        let expected = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(classify(403, remaining: "0", reset: "1800000000") == .rateLimited(retryAfter: expected))
    }

    @Test func rateLimitWithoutAnyHeaderWaitsAMinute() {
        #expect(classify(429) == .rateLimited(retryAfter: now.addingTimeInterval(60)))
        #expect(classify(403, bodyMentionsRateLimit: true) == .rateLimited(retryAfter: now.addingTimeInterval(60)))
    }

    @Test func aPlain403IsNotARateLimit() {
        #expect(classify(403) == .server(status: 403))
        #expect(classify(403, remaining: "4999", reset: "1800000000") == .server(status: 403))
    }

    @Test func otherStatusCodes() {
        #expect(classify(500) == .server(status: 500))
        #expect(classify(502) == .server(status: 502))
        #expect(classify(404) == .server(status: 404))
    }

    // MARK: Network failures

    @Test func networkFailuresGetPlainNames() {
        #expect(GitHubError.from(urlError: URLError(.notConnectedToInternet)) == .offline)
        #expect(GitHubError.from(urlError: URLError(.networkConnectionLost)) == .offline)
        #expect(GitHubError.from(urlError: URLError(.cannotFindHost)) == .offline)
        #expect(GitHubError.from(urlError: URLError(.timedOut)) == .timedOut)
        #expect(GitHubError.from(urlError: URLError(.badServerResponse)) == .network)
        #expect(GitHubError.from(urlError: URLError(.secureConnectionFailed)) == .network)
    }

    // MARK: Messages

    @Test func messagesAreReadableAndNeverMentionCredentials() {
        let all: [GitHubError] = [
            .noToken, .invalidToken, .insufficientScope, .offline, .timedOut, .network,
            .rateLimited(retryAfter: nil), .rateLimited(retryAfter: now),
            .server(status: 500), .server(status: 403), .graphQL("Could not resolve to a User."),
            .unexpectedResponse,
        ]
        for error in all {
            let text = error.message
            #expect(!text.isEmpty)
            #expect(!text.localizedCaseInsensitiveContains("bearer"), "\(error)")
            #expect(!text.localizedCaseInsensitiveContains("authorization"), "\(error)")
        }
    }

    @Test func serverMessagesSayWhoseProblemItIs() {
        #expect(GitHubError.server(status: 503).message.contains("GitHub is having problems"))
        #expect(GitHubError.server(status: 403).message.contains("refused"))
    }

    @Test func rateLimitMessageMentionsTheWait() {
        #expect(GitHubError.rateLimited(retryAfter: now).message.contains("Waiting until"))
        #expect(GitHubError.rateLimited(retryAfter: nil).message.contains("later"))
    }
}
