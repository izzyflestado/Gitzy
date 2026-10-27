import Foundation
import Testing
@testable import Gitzy

/// Builds day lists for the tests. It uses Foundation's calendar (fixed to UTC) on purpose:
/// that is an independent way of getting dates right, to check Gitzy's own date arithmetic against.
nonisolated enum TestDays {
    private static func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    static func date(_ iso: String) -> Date {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        return utcCalendar().date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    static func iso(_ date: Date) -> String {
        let c = utcCalendar().dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The date `offset` days after (or before, when negative) `iso`.
    static func shift(_ isoDate: String, by offset: Int) -> String {
        let moved = utcCalendar().date(byAdding: .day, value: offset, to: date(isoDate)) ?? date(isoDate)
        return iso(moved)
    }

    /// One day per count, oldest first, starting on `start`, one calendar day apart.
    static func days(from start: String, counts: [Int]) -> [ContributionDay] {
        let calendar = utcCalendar()
        return counts.enumerated().map { offset, count in
            let day = calendar.date(byAdding: .day, value: offset, to: date(start)) ?? date(start)
            return ContributionDay(
                date: iso(day),
                count: count,
                level: count == 0 ? .none : .first,
                weekday: calendar.component(.weekday, from: day) - 1   // Sunday = 0
            )
        }
    }

    /// Days that end on `end` (inclusive), one per count, oldest first.
    static func days(endingOn end: String, counts: [Int]) -> [ContributionDay] {
        days(from: shift(end, by: -(counts.count - 1)), counts: counts)
    }
}

nonisolated struct StreakCalculatorTests {

    // MARK: Today and yesterday

    @Test func emptyListHasNoStreak() {
        #expect(StreakCalculator.currentStreak(in: []) == StreakResult(length: 0, reachesOldestDay: false))
    }

    @Test func streakEndingToday() {
        let days = TestDays.days(endingOn: "2026-10-26", counts: [0, 0, 3, 2, 1])
        #expect(StreakCalculator.currentStreak(in: days) == StreakResult(length: 3, reachesOldestDay: false))
    }

    @Test func emptyTodayDoesNotBreakTheStreak() {
        let days = TestDays.days(endingOn: "2026-10-26", counts: [0, 1, 1, 0])
        #expect(StreakCalculator.currentStreak(in: days).length == 2)
    }

    @Test func todayAndYesterdayEmptyMeansNoStreak() {
        let days = TestDays.days(endingOn: "2026-10-26", counts: [5, 5, 0, 0])
        #expect(StreakCalculator.currentStreak(in: days) == StreakResult(length: 0, reachesOldestDay: false))
    }

    @Test func onlyTodayHasContributions() {
        let days = TestDays.days(endingOn: "2026-10-26", counts: [0, 0, 4])
        #expect(StreakCalculator.currentStreak(in: days).length == 1)
    }

    @Test func singleDays() {
        #expect(StreakCalculator.currentStreak(in: TestDays.days(from: "2026-10-26", counts: [1]))
                == StreakResult(length: 1, reachesOldestDay: true))
        #expect(StreakCalculator.currentStreak(in: TestDays.days(from: "2026-10-26", counts: [0]))
                == StreakResult(length: 0, reachesOldestDay: false))
    }

    // MARK: Gaps and the oldest day

    @Test func aGapEndsTheStreak() {
        let days = TestDays.days(endingOn: "2026-10-26", counts: [1, 1, 0, 1, 1, 1])
        #expect(StreakCalculator.currentStreak(in: days) == StreakResult(length: 3, reachesOldestDay: false))
    }

    @Test func streakReachingTheOldestDayIsFlagged() {
        let days = TestDays.days(endingOn: "2026-10-26", counts: [2, 1, 1, 1])
        #expect(StreakCalculator.currentStreak(in: days) == StreakResult(length: 4, reachesOldestDay: true))
    }

    @Test func emptyTodayWithStreakReachingTheOldestDay() {
        let days = TestDays.days(endingOn: "2026-10-26", counts: [2, 1, 0])
        #expect(StreakCalculator.currentStreak(in: days) == StreakResult(length: 2, reachesOldestDay: true))
    }

    @Test func aMissingDateEndsTheStreakEvenWhenCountsArePositive() {
        let days = [
            ContributionDay(date: "2024-02-28", count: 1, level: .first, weekday: 3),
            ContributionDay(date: "2024-03-01", count: 1, level: .first, weekday: 5),
        ]
        #expect(StreakCalculator.currentStreak(in: days) == StreakResult(length: 1, reachesOldestDay: false))
    }

    // MARK: Calendar edges

    @Test func streakAcrossNewYear() {
        let days = TestDays.days(from: "2025-12-29", counts: [1, 1, 1, 1, 1, 1])
        #expect(days.map(\.date) == ["2025-12-29", "2025-12-30", "2025-12-31", "2026-01-01", "2026-01-02", "2026-01-03"])
        #expect(StreakCalculator.currentStreak(in: days).length == 6)
    }

    @Test func streakAcrossALeapDay() {
        let leap = TestDays.days(from: "2024-02-27", counts: [1, 1, 1, 1])
        #expect(leap.map(\.date) == ["2024-02-27", "2024-02-28", "2024-02-29", "2024-03-01"])
        #expect(StreakCalculator.currentStreak(in: leap).length == 4)

        let ordinary = TestDays.days(from: "2023-02-27", counts: [1, 1, 1])
        #expect(ordinary.map(\.date) == ["2023-02-27", "2023-02-28", "2023-03-01"])
        #expect(StreakCalculator.currentStreak(in: ordinary).length == 3)
    }

    // MARK: Long streaks found by reaching into earlier years

    @Test func fourHundredDayStreakAcrossTwoWindows() {
        let end = "2026-10-26"
        let lastYear = TestDays.days(endingOn: end, counts: Array(repeating: 1, count: 365))
        #expect(StreakCalculator.currentStreak(in: lastYear) == StreakResult(length: 365, reachesOldestDay: true))

        // The window before it: a quiet day, then 35 days of contributions right up to the day before.
        let dayBefore = TestDays.shift(lastYear[0].date, by: -1)
        let earlier = TestDays.days(endingOn: dayBefore, counts: [0] + Array(repeating: 1, count: 35))

        let merged = StreakCalculator.merge([lastYear, earlier])
        #expect(StreakCalculator.currentStreak(in: merged) == StreakResult(length: 400, reachesOldestDay: false))
    }

    // MARK: Merging

    @Test func mergeSortsAndRemovesDuplicates() {
        let a = TestDays.days(from: "2026-01-03", counts: [1, 1])
        let b = TestDays.days(from: "2026-01-01", counts: [1, 1, 1])
        let merged = StreakCalculator.merge([a, b])
        #expect(merged.map(\.date) == ["2026-01-01", "2026-01-02", "2026-01-03", "2026-01-04"])
    }

    @Test func mergeKeepsTheLargerCount() {
        let zero = [ContributionDay(date: "2026-01-01", count: 0, level: .none, weekday: 4)]
        let five = [ContributionDay(date: "2026-01-01", count: 5, level: .third, weekday: 4)]
        #expect(StreakCalculator.merge([zero, five]).first?.count == 5)
        #expect(StreakCalculator.merge([five, zero]).first?.count == 5)
    }

    // MARK: Date arithmetic

    @Test func knownDayNumbers() {
        #expect(StreakCalculator.dayNumber(of: "1970-01-01") == 0)
        #expect(StreakCalculator.dayNumber(of: "1970-01-02") == 1)
        #expect(StreakCalculator.dayNumber(of: "1969-12-31") == -1)
        #expect(StreakCalculator.dayNumber(of: "2000-03-01") == 11_017)
    }

    @Test func invalidDatesHaveNoDayNumber() {
        #expect(StreakCalculator.dayNumber(of: "") == nil)
        #expect(StreakCalculator.dayNumber(of: "not-a-date") == nil)
        #expect(StreakCalculator.dayNumber(of: "2025-13-01") == nil)
        #expect(StreakCalculator.dayNumber(of: "2025-00-10") == nil)
        #expect(StreakCalculator.dayNumber(of: "2025-01") == nil)
    }

    @Test func dayNumbersMatchFoundationForTwoCenturies() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var day = try #require(calendar.date(from: DateComponents(year: 1900, month: 1, day: 1)))
        let last = try #require(calendar.date(from: DateComponents(year: 2100, month: 12, day: 31)))
        while day <= last {
            let expected = Int((day.timeIntervalSince1970 / 86_400).rounded())
            let text = TestDays.iso(day)
            #expect(StreakCalculator.dayNumber(of: text) == expected, "\(text)")
            day = try #require(calendar.date(byAdding: .day, value: 1, to: day))
        }
    }
}
