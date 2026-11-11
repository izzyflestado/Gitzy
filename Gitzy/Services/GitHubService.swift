import Foundation

nonisolated struct TokenInfo: Equatable, Sendable {
    let login: String
    /// The scopes GitHub reports for a classic token. Nil when GitHub does not say.
    let scopes: [String]?
}

/// All talking to GitHub. It contacts two kinds of address, both over HTTPS:
/// - https://api.github.com/graphql, for everything, with the token;
/// - GitHub's profile-picture servers (see AvatarSource), only to download one small picture, never with the token.
/// It is an actor so its small year cache is safe to touch from any thread.
actor GitHubService {
    private static let endpoint = URL(string: "https://api.github.com/graphql")!
    private static let firstGitHubYear = 2008
    private static let yearsPerRequest = 4
    /// A 96 px profile picture is a few kilobytes. Anything this large is not one.
    private static let maxAvatarBytes = 1_000_000

    private let session: URLSession
    /// Whole calendar years that are over. They never change again, so they are fetched once.
    /// Kept in memory only, and dropped when the account changes.
    private var closedYears: [Int: [ContributionDay]] = [:]
    private var cachedLogin: String?

    init() {
        let configuration = URLSessionConfiguration.ephemeral   // no cookies, no disk cache
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration)
    }

    func clearCache() {
        closedYears = [:]
        cachedLogin = nil
    }

    /// Checks a token with the smallest possible request.
    func validate(token: String) async throws -> TokenInfo {
        let reply = try await post(query: GitHubQueries.viewerLogin, variables: [:], token: token)
        let parsed = try GitHubParser.parse(reply.data, rateLimitExhausted: reply.rateLimitExhausted, retryAfter: reply.resetDate)
        return TokenInfo(login: parsed.login, scopes: reply.scopes)
    }

    /// Fetches the 12-month graph and the current streak.
    /// If the streak reaches the oldest day of that window, earlier years are fetched
    /// (several per request) until the streak breaks.
    func loadContributions(token: String) async throws -> ContributionSnapshot {
        let reply = try await post(query: GitHubQueries.lastYear, variables: [:], token: token)
        let parsed = try GitHubParser.parse(reply.data, rateLimitExhausted: reply.rateLimitExhausted, retryAfter: reply.resetDate)
        guard let calendar = parsed.calendars.values.first else { throw GitHubError.unexpectedResponse }

        if parsed.login != cachedLogin {
            closedYears = [:]
            cachedLogin = parsed.login
        }

        var days = StreakCalculator.merge([calendar.weeks.flatMap { $0 }])
        var streak = StreakCalculator.currentStreak(in: days)

        if streak.reachesOldestDay,
           let newest = days.last, let oldest = days.first,
           let currentYear = Self.year(of: newest.date), var year = Self.year(of: oldest.date) {
            while streak.reachesOldestDay && year >= Self.firstGitHubYear {
                try Task.checkCancellation()
                let lowest = max(year - Self.yearsPerRequest + 1, Self.firstGitHubYear)
                let batch = Array(stride(from: year, through: lowest, by: -1))
                let older = try await loadYears(batch, currentYear: currentYear, token: token)
                days = StreakCalculator.merge([days] + older)
                streak = StreakCalculator.currentStreak(in: days)
                year = lowest - 1
            }
        }

        return ContributionSnapshot(
            login: parsed.login,
            name: parsed.name,
            avatarURL: AvatarSource.validated(parsed.avatarURL),
            weeks: calendar.weeks,
            totalContributions: calendar.total,
            currentStreak: streak.length,
            fetchedAt: Date()
        )
    }

    /// Downloads the profile picture. This is the one request that does not go to api.github.com,
    /// and the one that never carries the token. The address has to pass AvatarSource first.
    /// Nothing is cached: the session keeps no disk cache, and the caller keeps the picture in memory only.
    func loadAvatar(from url: URL) async throws -> Data {
        guard let safe = AvatarSource.validated(url.absoluteString) else { throw GitHubError.unexpectedResponse }
        var request = URLRequest(url: safe)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Gitzy", forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw GitHubError.from(urlError: error)
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count <= Self.maxAvatarBytes else {
            throw GitHubError.unexpectedResponse
        }
        return data
    }

    /// One load of "Recent activity". It asks about 30 days at a time and steps further back until about ten rows
    /// are found, at most three requests. `end` is where to start (now, or where the last load stopped) and `limit`
    /// is the oldest moment it may reach. The reply says where it stopped, so "Load more" can carry on from there.
    func loadActivity(token: String, endingAt end: Date, notBefore limit: Date) async throws -> ActivityPage {
        let wanted = 10
        let maxRequests = 3
        var items: [ActivityItem] = []
        var cursor = end
        var requests = 0
        while requests < maxRequests, let window = ActivityWindows.window(endingAt: cursor, notBefore: limit) {
            try Task.checkCancellation()
            let request = ActivityQuery.make(from: window.from, to: window.to)
            let reply = try await post(query: request.query, variables: request.variables, token: token)
            let found = try ActivityParser.parse(reply.data, rateLimitExhausted: reply.rateLimitExhausted, retryAfter: reply.resetDate)
            items = ActivityMerge.appending(found, to: items)
            cursor = window.from.addingTimeInterval(-1)
            requests += 1
            if items.count >= wanted { break }
        }
        return ActivityPage(items: items, nextEnd: cursor)
    }

    // MARK: Private

    private func loadYears(_ years: [Int], currentYear: Int, token: String) async throws -> [[ContributionDay]] {
        var loaded: [Int: [ContributionDay]] = [:]
        let missing = years.filter { closedYears[$0] == nil }
        if !missing.isEmpty {
            let request = GitHubQueries.calendarYears(missing)
            let reply = try await post(query: request.query, variables: request.variables, token: token)
            let parsed = try GitHubParser.parse(reply.data, rateLimitExhausted: reply.rateLimitExhausted, retryAfter: reply.resetDate)
            for year in missing {
                guard let calendar = parsed.calendars["y\(year)"] else { throw GitHubError.unexpectedResponse }
                let days = calendar.weeks.flatMap { $0 }
                loaded[year] = days
                if year < currentYear { closedYears[year] = days }
            }
        }
        return years.map { closedYears[$0] ?? loaded[$0] ?? [] }
    }

    private static func year(of date: String) -> Int? {
        Int(date.prefix(4))
    }

    private struct Reply {
        let data: Data
        let scopes: [String]?
        let rateLimitExhausted: Bool
        let resetDate: Date?
    }

    private func post(query: String, variables: [String: String], token: String) async throws -> Reply {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("Gitzy", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["query": query, "variables": variables]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw GitHubError.from(urlError: error)
        }
        guard let http = response as? HTTPURLResponse else { throw GitHubError.unexpectedResponse }

        let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining")
        let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset")
        let bodyText = String(data: data.prefix(2_000), encoding: .utf8)?.lowercased() ?? ""
        if let error = GitHubError.classify(
            status: http.statusCode,
            retryAfter: http.value(forHTTPHeaderField: "Retry-After"),
            rateLimitRemaining: remaining,
            rateLimitReset: reset,
            bodyMentionsRateLimit: bodyText.contains("rate limit")
        ) {
            throw error
        }

        let scopes = http.value(forHTTPHeaderField: "X-OAuth-Scopes").map { header in
            header.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return Reply(
            data: data,
            scopes: scopes,
            rateLimitExhausted: remaining == "0",
            resetDate: reset.flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
