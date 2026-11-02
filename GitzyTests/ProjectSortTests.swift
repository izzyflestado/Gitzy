import Foundation
import Testing
@testable import Gitzy

nonisolated struct ProjectSortTests {

    private func row(_ path: String, missing: Bool = false) -> ProjectRow {
        ProjectRow(
            project: GitProject(path: path),
            status: ProjectStatus(head: .branch("main"), isMissing: missing)
        )
    }

    private func names(_ rows: [ProjectRow]) -> [String] { rows.map(\.project.name) }

    private func date(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    // MARK: Custom

    @Test func customReturnsTheRowsUntouched() {
        let rows = [row("/p/zeta"), row("/p/alpha"), row("/p/mid")]
        let result = ProjectSorter.sorted(rows, by: .custom, activity: [:], addedOrder: [])
        #expect(result == rows)
    }

    // MARK: Name

    @Test func nameIgnoresCase() {
        let rows = [row("/p/beta"), row("/p/Alpha"), row("/p/gamma")]
        let result = ProjectSorter.sorted(rows, by: .name, activity: [:], addedOrder: [])
        #expect(names(result) == ["Alpha", "beta", "gamma"])
    }

    @Test func nameCountsNumbersTheWayPeopleDo() {
        let rows = [row("/p/app10"), row("/p/app2"), row("/p/app1")]
        let result = ProjectSorter.sorted(rows, by: .name, activity: [:], addedOrder: [])
        #expect(names(result) == ["app1", "app2", "app10"])
    }

    @Test func sameNamesAreOrderedByPathSoTheOrderNeverFlips() {
        let rows = [row("/b/app"), row("/a/app")]
        let result = ProjectSorter.sorted(rows, by: .name, activity: [:], addedOrder: [])
        #expect(result.map(\.project.path) == ["/a/app", "/b/app"])
    }

    // MARK: Recently added

    @Test func recentlyAddedPutsTheNewestFirst() {
        let rows = [row("/p/one"), row("/p/two"), row("/p/three")]
        let added = ["/p/one", "/p/two", "/p/three"]
        let result = ProjectSorter.sorted(rows, by: .recentlyAdded, activity: [:], addedOrder: added)
        #expect(names(result) == ["three", "two", "one"])
    }

    @Test func recentlyAddedIgnoresWhereTheRowsWereDragged() {
        // Dragged into a different order than they were added in.
        let rows = [row("/p/three"), row("/p/one"), row("/p/two")]
        let added = ["/p/one", "/p/two", "/p/three"]
        let result = ProjectSorter.sorted(rows, by: .recentlyAdded, activity: [:], addedOrder: added)
        #expect(names(result) == ["three", "two", "one"])
    }

    @Test func aProjectMissingFromTheAddOrderCountsAsOldest() {
        let rows = [row("/p/stranger"), row("/p/one"), row("/p/two")]
        let result = ProjectSorter.sorted(rows, by: .recentlyAdded, activity: [:], addedOrder: ["/p/one", "/p/two"])
        #expect(names(result) == ["two", "one", "stranger"])
    }

    // MARK: Last commit

    @Test func lastCommitPutsTheNewestFirstAndUndatedLast() {
        let rows = [row("/p/old"), row("/p/none"), row("/p/new"), row("/p/mid")]
        let activity = ["/p/old": date(1_000), "/p/new": date(3_000), "/p/mid": date(2_000)]
        let result = ProjectSorter.sorted(rows, by: .lastCommit, activity: activity, addedOrder: [])
        #expect(names(result) == ["new", "mid", "old", "none"])
    }

    @Test func lastCommitTiesAndUndatedProjectsFallBackToName() {
        let rows = [row("/p/b"), row("/p/a"), row("/p/d"), row("/p/c")]
        let activity = ["/p/b": date(5_000), "/p/a": date(5_000)]
        let result = ProjectSorter.sorted(rows, by: .lastCommit, activity: activity, addedOrder: [])
        #expect(names(result) == ["a", "b", "c", "d"])
    }

    // MARK: Every mode keeps every row

    @Test func nothingIsLostOrDuplicated() {
        let rows = [row("/p/c"), row("/p/a"), row("/p/b", missing: true), row("/p/d")]
        for sort in ProjectSort.allCases {
            let result = ProjectSorter.sorted(rows, by: sort, activity: ["/p/a": date(1)], addedOrder: ["/p/d", "/p/c"])
            #expect(result.count == rows.count, "\(sort)")
            #expect(Set(result.map(\.id)) == Set(rows.map(\.id)), "\(sort)")
        }
    }

    @Test func anEmptyListStaysEmpty() {
        for sort in ProjectSort.allCases {
            #expect(ProjectSorter.sorted([], by: sort, activity: [:], addedOrder: []).isEmpty)
        }
    }

    // MARK: The saved add-order

    @Test func reconcilingKeepsTheSavedOrderAndDropsGoneProjects() {
        let result = ProjectSorter.reconciledAddedOrder(["/a", "/gone", "/b"], projects: ["/b", "/a"])
        #expect(result == ["/a", "/b"])
    }

    @Test func reconcilingAppendsProjectsTheSavedOrderNeverListed() {
        let result = ProjectSorter.reconciledAddedOrder(["/a"], projects: ["/c", "/a", "/b"])
        #expect(result == ["/a", "/c", "/b"])
    }

    @Test func reconcilingNothingSavedUsesTheCurrentOrder() {
        #expect(ProjectSorter.reconciledAddedOrder([], projects: ["/x", "/y"]) == ["/x", "/y"])
    }

    @Test func reconcilingDropsDuplicates() {
        #expect(ProjectSorter.reconciledAddedOrder(["/a", "/a", "/b"], projects: ["/a", "/b"]) == ["/a", "/b"])
    }

    @Test func reconcilingWithNoProjectsGivesNothing() {
        #expect(ProjectSorter.reconciledAddedOrder(["/a"], projects: []).isEmpty)
    }

    // MARK: The choices themselves

    @Test func theSavedNamesNeverChange() {
        #expect(ProjectSort.allCases.map(\.rawValue) == ["custom", "name", "recentlyAdded", "lastCommit"])
    }

    @Test func everyChoiceHasLabelsAndTheyAreDistinct() {
        for sort in ProjectSort.allCases {
            #expect(!sort.menuLabel.isEmpty)
            #expect(!sort.shortLabel.isEmpty)
        }
        #expect(Set(ProjectSort.allCases.map(\.menuLabel)).count == ProjectSort.allCases.count)
    }
}
