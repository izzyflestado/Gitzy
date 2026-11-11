import Foundation
import Observation

/// Today's commits on this Mac, for the dot on the profile picture.
///
/// ContributionStore calls `refresh()` every time it refreshes, which includes every time the popover opens.
/// It reads the saved project list (the same one ProjectStore keeps) and each project's log file, on a background task.
@Observable
final class TodayCommitsStore {
    private(set) var local = LocalToday.none

    /// Counts every refresh, so a read that was overtaken by a newer one can never overwrite it.
    @ObservationIgnored private var serial = 0

    func refresh() {
        let paths = UserDefaults.standard.stringArray(forKey: ProjectStore.defaultsKey) ?? []
        let start = Calendar.current.startOfDay(for: Date())
        serial += 1
        let mine = serial
        Task {
            let result = await Task.detached { TodayCommits.summary(forProjectsAt: paths, since: start) }.value
            guard mine == serial else { return }
            if result != local { local = result }
        }
    }
}
