import Foundation
import Observation

/// The Local view of "Recent activity": each commit made on this Mac in the saved projects over the last 30 days.
///
/// Nothing is saved. Every refresh reads the projects' log files again (see LocalCommits), so the list is never stale
/// and nothing older than 30 days is kept. Only a first few rows are shown, and "Load more" shows more of what was read.
@Observable
final class LocalActivityStore {
    /// How many rows show at first, and how many more each "Load more" adds.
    static let pageSize = 10

    private var all: [ActivityItem] = []
    private var shown = LocalActivityStore.pageSize
    private(set) var isLoading = false
    private(set) var hasLoaded = false

    /// Newest first.
    var items: [ActivityItem] { Array(all.prefix(shown)) }
    var hasMore: Bool { all.count > shown }

    /// Counts every refresh, so a read that was overtaken by a newer one can never overwrite it.
    @ObservationIgnored private var serial = 0

    /// Reads the saved projects (the same list ProjectStore keeps) and their logs, on a background task.
    func refresh() {
        let paths = UserDefaults.standard.stringArray(forKey: ProjectStore.defaultsKey) ?? []
        let since = Date().addingTimeInterval(-Double(LocalCommits.days) * 86_400)
        serial += 1
        let mine = serial
        isLoading = true
        Task {
            let found = await Task.detached { LocalCommits.recent(forProjectsAt: paths, since: since) }.value
            guard mine == serial else { return }
            if found != all { all = found }
            hasLoaded = true
            isLoading = false
        }
    }

    func loadMore() {
        shown += Self.pageSize
    }
}
