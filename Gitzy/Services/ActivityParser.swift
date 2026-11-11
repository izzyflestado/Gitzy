import Foundation

/// The one extra request behind "Recent activity". It goes to the same address as everything else
/// (https://api.github.com/graphql, with the token) and asks for the same kind of public information as the
/// contribution summary on a GitHub profile: which repositories got commits on which days, and which pull requests,
/// issues, reviews and repositories were opened. It never asks for commit messages, file names or code.
///
/// Every list is capped. Commits come grouped by repository and day, so a 30-day window needs at most 31 days each.
/// The other lists come newest first (that is GitHub's default order) and are capped at 50 a window.
nonisolated enum ActivityQuery {
    private static let perRepository = 31
    private static let perList = 50

    static func make(from: Date, to: Date) -> (query: String, variables: [String: String]) {
        let reference = "title number url repository { nameWithOwner }"
        let query = """
        query($from: DateTime!, $to: DateTime!) { viewer { contributionsCollection(from: $from, to: $to) { \
        commitContributionsByRepository(maxRepositories: 25) { repository { nameWithOwner url } \
        contributions(first: \(perRepository)) { nodes { commitCount occurredAt } } } \
        pullRequestContributions(first: \(perList)) { nodes { occurredAt pullRequest { \(reference) } } } \
        issueContributions(first: \(perList)) { nodes { occurredAt issue { \(reference) } } } \
        pullRequestReviewContributions(first: \(perList)) { nodes { occurredAt pullRequest { \(reference) } } } \
        repositoryContributions(first: \(perList)) { nodes { occurredAt repository { nameWithOwner url } } } \
        } } }
        """
        let formatter = ISO8601DateFormatter()   // UTC, no fractional seconds: "2026-11-10T12:00:00Z"
        return (query, ["from": formatter.string(from: from), "to": formatter.string(from: to)])
    }
}

/// Decides which addresses a click on a row may open. Only a plain HTTPS address on github.com is accepted,
/// with no user name, password or port, so a changed or odd reply can never send a click somewhere else.
nonisolated enum GitHubLink {
    private static let maxLength = 300

    /// The address if it is a plain https://github.com/... address, otherwise nil.
    static func validated(_ text: String?) -> URL? {
        guard let text, text.count <= maxLength,
              let components = URLComponents(string: text),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.host?.lowercased() == "github.com"
        else { return nil }
        return components.url
    }

    /// https://github.com/owner/name, built from a repository name that already passed ActivityText.repoName.
    static func repository(_ nameWithOwner: String) -> URL? {
        URL(string: "https://github.com/\(nameWithOwner)")
    }
}

/// Cleans text that came from other people (repository names, pull request titles) before it is shown.
nonisolated enum ActivityText {
    private static let maxTitleLength = 120
    private static let maxRepoLength = 140

    /// "owner/name", made only of the characters GitHub allows there. Anything else is not shown at all.
    static func repoName(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw.count <= maxRepoLength else { return nil }
        let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        let allowed = raw.allSatisfy { $0 == "/" || $0 == "-" || $0 == "_" || $0 == "." || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
        return allowed ? raw : nil
    }

    /// A one-line title: line breaks and tabs become spaces, repeated spaces collapse, and the characters that
    /// flip the direction of text (which could make one title look like another) are dropped. Long titles are cut.
    static func title(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var cleaned = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            if isDirectionControl(scalar) { continue }
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator:
                cleaned.append(" ")
            default:
                cleaned.append(scalar)
            }
        }
        let text = String(cleaned)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard !text.isEmpty else { return nil }
        guard text.count > maxTitleLength else { return text }
        return String(text.prefix(maxTitleLength - 1)) + "…"
    }

    private static func isDirectionControl(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x061C, 0x200E, 0x200F, 0x202A...0x202E, 0x2066...0x2069:
            return true
        default:
            return false
        }
    }
}

/// Turns GitHub's answer to the ActivityQuery into rows, or throws a GitHubError.
/// It is forgiving about what it reads: a row with something missing or odd is left out, and the rest still show.
nonisolated enum ActivityParser {
    static func parse(_ data: Data, rateLimitExhausted: Bool = false, retryAfter: Date? = nil) throws -> [ActivityItem] {
        let envelope: ActivityEnvelope
        do {
            envelope = try JSONDecoder().decode(ActivityEnvelope.self, from: data)
        } catch {
            throw GitHubError.unexpectedResponse
        }

        if let errors = envelope.errors, !errors.isEmpty {
            throw GitHubError.from(
                graphQLErrors: errors.map { ($0.type, $0.message) },
                rateLimitExhausted: rateLimitExhausted,
                retryAfter: retryAfter
            )
        }
        guard let collection = envelope.data?.viewer?.contributionsCollection else { throw GitHubError.unexpectedResponse }

        let dates = DateReader()
        var items: [ActivityItem] = []

        for group in collection.commitContributionsByRepository ?? [] {
            guard let repo = ActivityText.repoName(group?.repository?.nameWithOwner) else { continue }
            let url = GitHubLink.validated(group?.repository?.url) ?? GitHubLink.repository(repo)
            for node in group?.contributions?.nodes ?? [] {
                guard let count = node?.commitCount, count > 0, let date = dates.read(node?.occurredAt) else { continue }
                items.append(ActivityItem(
                    id: "commits|\(repo)|\(Int(date.timeIntervalSince1970))",
                    kind: .commits,
                    action: count == 1 ? "Made 1 commit" : "Made \(count) commits",
                    repo: repo,
                    detail: nil,
                    date: date,
                    url: url
                ))
            }
        }

        for node in collection.pullRequestContributions?.nodes ?? [] {
            if let item = titled(node?.pullRequest, occurredAt: node?.occurredAt, kind: .pullRequest, action: "Opened pull request", dates: dates) {
                items.append(item)
            }
        }
        for node in collection.issueContributions?.nodes ?? [] {
            if let item = titled(node?.issue, occurredAt: node?.occurredAt, kind: .issue, action: "Opened issue", dates: dates) {
                items.append(item)
            }
        }
        for node in collection.pullRequestReviewContributions?.nodes ?? [] {
            if let item = titled(node?.pullRequest, occurredAt: node?.occurredAt, kind: .review, action: "Reviewed pull request", dates: dates) {
                items.append(item)
            }
        }

        for node in collection.repositoryContributions?.nodes ?? [] {
            guard let repo = ActivityText.repoName(node?.repository?.nameWithOwner), let date = dates.read(node?.occurredAt) else { continue }
            items.append(ActivityItem(
                id: "repository|\(repo)|\(Int(date.timeIntervalSince1970))",
                kind: .repository,
                action: "Created repository",
                repo: repo,
                detail: nil,
                date: date,
                url: GitHubLink.validated(node?.repository?.url) ?? GitHubLink.repository(repo)
            ))
        }

        return ActivityMerge.appending(items, to: [])
    }

    /// A pull request or an issue: "#12 Title", in a repository, at a time.
    private static func titled(_ reference: ReferencePayload?, occurredAt: String?, kind: ActivityKind, action: String, dates: DateReader) -> ActivityItem? {
        guard let reference,
              let repo = ActivityText.repoName(reference.repository?.nameWithOwner),
              let date = dates.read(occurredAt)
        else { return nil }

        let title = ActivityText.title(reference.title)
        let detail: String?
        if let number = reference.number, number > 0 {
            detail = title.map { "#\(number) \($0)" } ?? "#\(number)"
        } else {
            detail = title
        }
        return ActivityItem(
            id: "\(action)|\(repo)|\(reference.number ?? 0)|\(Int(date.timeIntervalSince1970))",
            kind: kind,
            action: action,
            repo: repo,
            detail: detail,
            date: date,
            url: GitHubLink.validated(reference.url) ?? GitHubLink.repository(repo)
        )
    }
}

/// GitHub writes dates like "2026-11-09T14:22:31Z". A reply with fractional seconds is read too.
/// A class, so the two formatters are made once per reply and not once per row.
private nonisolated final class DateReader {
    private let plain = ISO8601DateFormatter()
    private let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func read(_ text: String?) -> Date? {
        guard let text else { return nil }
        return plain.date(from: text) ?? fractional.date(from: text)
    }
}

// MARK: JSON shapes. Every field is optional, so one odd entry cannot spoil the rest.

private nonisolated struct ActivityEnvelope: Decodable {
    let data: ActivityData?
    let errors: [ActivityErrorPayload]?
}

private nonisolated struct ActivityErrorPayload: Decodable {
    let type: String?
    let message: String
}

private nonisolated struct ActivityData: Decodable {
    let viewer: ActivityViewer?
}

private nonisolated struct ActivityViewer: Decodable {
    let contributionsCollection: ActivityCollection?
}

private nonisolated struct ActivityCollection: Decodable {
    let commitContributionsByRepository: [CommitGroupPayload?]?
    let pullRequestContributions: NodesPayload<PullRequestNodePayload>?
    let issueContributions: NodesPayload<IssueNodePayload>?
    let pullRequestReviewContributions: NodesPayload<PullRequestNodePayload>?
    let repositoryContributions: NodesPayload<RepositoryNodePayload>?
}

private nonisolated struct NodesPayload<Node: Decodable>: Decodable {
    let nodes: [Node?]?
}

private nonisolated struct RepositoryPayload: Decodable {
    let nameWithOwner: String?
    let url: String?
}

private nonisolated struct CommitGroupPayload: Decodable {
    let repository: RepositoryPayload?
    let contributions: NodesPayload<CommitNodePayload>?
}

private nonisolated struct CommitNodePayload: Decodable {
    let commitCount: Int?
    let occurredAt: String?
}

/// A pull request or an issue.
private nonisolated struct ReferencePayload: Decodable {
    let title: String?
    let number: Int?
    let url: String?
    let repository: RepositoryPayload?
}

private nonisolated struct PullRequestNodePayload: Decodable {
    let occurredAt: String?
    let pullRequest: ReferencePayload?
}

private nonisolated struct IssueNodePayload: Decodable {
    let occurredAt: String?
    let issue: ReferencePayload?
}

private nonisolated struct RepositoryNodePayload: Decodable {
    let occurredAt: String?
    let repository: RepositoryPayload?
}
