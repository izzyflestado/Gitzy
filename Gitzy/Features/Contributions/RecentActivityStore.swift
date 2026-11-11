import Foundation
import Observation

/// The "Recent activity" list on the GitHub tab: what it shows, and how it loads.
///
/// ContributionStore owns one and calls `refresh(login:)` after each successful contribution refresh, and `reset()`
/// when the account is disconnected. Loading is a separate request from the graph, so if it fails the graph is not
/// affected, and the rows that were already loaded stay on screen.
///
/// The token is never held here. It is read from its private file (see TokenFile) for each load and handed straight to
/// GitHubService.
@Observable
final class RecentActivityStore {
    /// Newest first.
    private(set) var items: [ActivityItem] = []
    private(set) var isLoading = false
    /// False until the first answer, or the first failure, so the view can tell "still loading" from "nothing there".
    private(set) var hasLoaded = false
    /// Why the last load failed. The rows that were already loaded stay on screen next to it.
    private(set) var error: String?
    /// True while GitHub may have older activity (the list reaches back at most a year).
    private(set) var hasMore = false
    /// How many days back the list reaches, for the "nothing found" message.
    private(set) var daysCovered = 0

    private let service = GitHubService()
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Counts every start and every reset. A load only writes its result while its number is still the latest,
    /// so a load that was replaced or cancelled can never write into newer state.
    @ObservationIgnored private var serial = 0
    @ObservationIgnored private var login: String?
    /// The list reaches back to this moment. "Load more" asks for what is just before it.
    @ObservationIgnored private var cursor: Date?
    /// Do not contact GitHub before this moment (rate limit).
    @ObservationIgnored private var blockedUntil: Date?

    private static let fallbackBlock: TimeInterval = 15 * 60

    // MARK: Loading

    /// Reads the newest activity again. Rows loaded further back with "Load more" are kept.
    /// A different account starts from nothing.
    func refresh(login newLogin: String) {
        if newLogin != login {
            reset()
            login = newLogin
        }
        start(older: false)
    }

    /// Loads the next stretch of older activity.
    func loadMore() {
        guard hasMore, !isLoading else { return }
        start(older: true)
    }

    /// For the "Try again" button, when the very first load failed.
    func retry() {
        guard !isLoading else { return }
        start(older: false)
    }

    /// Forgets everything: on Disconnect, and when another account connects.
    func reset() {
        serial += 1
        task?.cancel()
        task = nil
        items = []
        isLoading = false
        hasLoaded = false
        error = nil
        hasMore = false
        daysCovered = 0
        login = nil
        cursor = nil
        blockedUntil = nil
    }

    // MARK: Private

    private func start(older: Bool) {
        if let until = blockedUntil, until > Date() {
            error = GitHubError.rateLimited(retryAfter: until).message
            hasLoaded = true
            return
        }
        serial += 1
        let mine = serial
        task?.cancel()
        isLoading = true
        error = nil
        task = Task { await load(older: older, serial: mine) }
    }

    private func load(older: Bool, serial mine: Int) async {
        defer {
            if mine == serial {
                isLoading = false
                task = nil
            }
        }

        let stored = await Task.detached { TokenFile.standard.load() }.value
        guard mine == serial else { return }
        let token: String
        switch stored {
        case .found(let value):
            token = value
        case .missing:
            // The contribution refresh deals with a missing token. Nothing to add here.
            hasLoaded = true
            return
        case .unreadable:
            error = "Gitzy could not read its saved token. Try Refresh again."
            hasLoaded = true
            return
        }

        let now = Date()
        let limit = now.addingTimeInterval(-Double(ActivityWindows.maxDaysBack) * 86_400)
        let end = older ? (cursor ?? now) : now

        do {
            let page = try await service.loadActivity(token: token, endingAt: end, notBefore: limit)
            guard mine == serial else { return }

            if older {
                items = ActivityMerge.appending(page.items, to: items)
                cursor = page.nextEnd
            } else {
                items = ActivityMerge.refreshing(items, with: page.items, coveredBack: page.nextEnd)
                // Keep a deeper cursor when "Load more" already went further back than this refresh did.
                if let deeper = cursor, deeper < page.nextEnd {
                    cursor = deeper
                } else {
                    cursor = page.nextEnd
                }
            }
            let reached = cursor ?? now
            hasMore = reached > limit
            daysCovered = max(0, Int((now.timeIntervalSince(reached) / 86_400).rounded()))
            hasLoaded = true
            blockedUntil = nil
        } catch is CancellationError {
            return
        } catch let failure as GitHubError {
            guard mine == serial else { return }
            if case .rateLimited(let retryAfter) = failure {
                blockedUntil = retryAfter ?? Date().addingTimeInterval(Self.fallbackBlock)
            }
            error = failure.message
            hasLoaded = true
        } catch {
            guard mine == serial else { return }
            self.error = GitHubError.network.message
            hasLoaded = true
        }
    }
}
