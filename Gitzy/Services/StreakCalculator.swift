import Foundation

nonisolated struct StreakResult: Equatable, Sendable {
    let length: Int
    /// True when the streak runs all the way back to the oldest day we have,
    /// which means older data could make it longer.
    let reachesOldestDay: Bool
}

/// Streak maths on GitHub's own dates. Dates are compared as plain calendar days,
/// never converted through a time zone.
nonisolated enum StreakCalculator {

    /// Days must be sorted oldest to newest and cover every day. The newest day is "today" as GitHub reports it.
    /// The current streak is the run of days with at least one contribution that ends today,
    /// or ends yesterday when today has none yet.
    static func currentStreak(in days: [ContributionDay]) -> StreakResult {
        guard var index = days.indices.last else {
            return StreakResult(length: 0, reachesOldestDay: false)
        }

        // Nothing yet today does not break the streak, so start from yesterday.
        if days[index].count == 0 {
            guard index > 0, days[index - 1].count > 0, isNextDay(days[index - 1], days[index]) else {
                return StreakResult(length: 0, reachesOldestDay: false)
            }
            index -= 1
        }

        var length = 1
        while index > 0 {
            let previous = days[index - 1]
            guard previous.count > 0, isNextDay(previous, days[index]) else {
                return StreakResult(length: length, reachesOldestDay: false)
            }
            length += 1
            index -= 1
        }
        return StreakResult(length: length, reachesOldestDay: true)
    }

    /// Combines day lists into one list sorted oldest to newest with one entry per date.
    /// If two lists disagree about a date, the larger count wins (a window that does not
    /// really cover a date can only ever report 0 for it).
    static func merge(_ lists: [[ContributionDay]]) -> [ContributionDay] {
        var byDate: [String: ContributionDay] = [:]
        for day in lists.joined() {
            if let existing = byDate[day.date], existing.count >= day.count { continue }
            byDate[day.date] = day
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    /// Days since 1970-01-01 for a "yyyy-MM-dd" string, using pure calendar arithmetic (no time zone involved).
    static func dayNumber(of isoDate: String) -> Int? {
        let parts = isoDate.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day) else { return nil }

        // Standard "days from civil" algorithm; years start in March so leap days fall at the end.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func isNextDay(_ earlier: ContributionDay, _ later: ContributionDay) -> Bool {
        guard let first = dayNumber(of: earlier.date), let second = dayNumber(of: later.date) else { return false }
        return second == first + 1
    }
}
