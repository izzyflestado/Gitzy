import CoreGraphics
import Foundation
import Testing
@testable import Gitzy

/// Which apps count as visible, and what the widget does about it.
///
/// The layouts below are the real ones read from a MacBook Air (1470 x 956) with Terminal, Brave, Xcode, Discord,
/// Obsidian and others, so the numbers are the ones the window list gave.
nonisolated struct AppVisibilityTests {

    // MARK: Helpers

    private func window(_ id: Int, _ app: String?, x: Double, y: Double = 33, width: Double, height: Double = 923, alpha: Double = 1) -> WindowSample {
        WindowSample(id: id, appID: app, bounds: CGRect(x: x, y: y, width: width, height: height), alpha: alpha)
    }

    private func coverage(_ windows: [WindowSample], minFraction: Double = 0.33) -> [String: AppCoverage] {
        let apps = WindowCoverage.apps(in: windows, minFraction: minFraction, minVisibleArea: 40_000)
        return Dictionary(uniqueKeysWithValues: apps.map { ($0.appID, $0) })
    }

    private func entry(id: Int, pid: Int, layer: Int = 0, alpha: Double = 1, x: Double, y: Double, width: Double, height: Double) -> [String: Any] {
        [
            kCGWindowNumber as String: id,
            kCGWindowOwnerPID as String: pid,
            kCGWindowLayer as String: layer,
            kCGWindowAlpha as String: alpha,
            kCGWindowBounds as String: CGRect(x: x, y: y, width: width, height: height).dictionaryRepresentation as NSDictionary,
        ]
    }

    // MARK: Covered windows

    @Test func tiledAppsAreVisibleAndTheOneBehindThemIsNot() {
        // Terminal left, Brave right, Xcode full width behind both.
        let apps = coverage([
            window(1, "terminal", x: 0, width: 735),
            window(2, "brave", x: 734, width: 736),
            window(3, "xcode", x: 0, width: 736),
        ])
        #expect(apps["terminal"]?.isVisible == true)
        #expect(apps["terminal"]?.fraction == 1)
        #expect(apps["brave"]?.isVisible == true)
        #expect(apps["xcode"]?.isVisible == false)
        #expect(apps["xcode"]?.fraction == 0)
    }

    @Test func aWindowPartlyCoveredKeepsItsUncoveredShare() throws {
        // Discord (full height, from x 201) in front of Terminal (x 0 to 735): 201 of its 735 points show.
        let apps = coverage([
            window(1, "discord", x: 201, width: 1269),
            window(2, "terminal", x: 0, width: 735),
            window(3, "xcode", x: 0, width: 520),
            window(4, "brave", x: 734, width: 736),
        ])
        let terminal = try #require(apps["terminal"])
        #expect(abs(terminal.fraction - 201.0 / 735.0) < 0.0001)
        #expect(terminal.isVisible == false)           // 27%, under the 33% default
        #expect(apps["discord"]?.isVisible == true)
        #expect(apps["xcode"]?.isVisible == false)
        #expect(apps["brave"]?.isVisible == false)
    }

    @Test func theThresholdDecidesWhereAPartlyCoveredAppCounts() throws {
        // Xcode is 520 wide with Discord over everything from x 201: 201 of 520 points show, about 39%.
        let windows = [
            window(1, "discord", x: 201, width: 1269),
            window(2, "xcode", x: 0, width: 520),
            window(3, "terminal", x: 0, width: 735),
        ]
        let xcode = try #require(coverage(windows)["xcode"])
        #expect(abs(xcode.fraction - 201.0 / 520.0) < 0.0001)
        #expect(xcode.isVisible == true)                                  // 39% is over 33%
        #expect(coverage(windows, minFraction: 0.40)["xcode"]?.isVisible == false)
        #expect(coverage(windows)["terminal"]?.isVisible == false)
    }

    @Test func halfOfAWindowShowingCountsAtThirtyThreePercent() {
        // Petrichor is full width with Obsidian over its left half. iCal is behind both.
        let apps = coverage([
            window(1, "obsidian", x: 0, width: 735),
            window(2, "petrichor", x: 0, width: 1470),
            window(3, "ical", x: 734, width: 736),
        ])
        #expect(apps["petrichor"]?.fraction == 0.5)
        #expect(apps["petrichor"]?.isVisible == true)
        #expect(apps["ical"]?.isVisible == false)
    }

    @Test func aFullscreenAppInFourPiecesIsOneVisibleApp() {
        // Brave fullscreen is a toolbar, a tab strip, a strip that overlaps both, and the page.
        let windows = [
            window(1895, "brave", x: 0, y: 33, width: 1470, height: 40),
            window(1894, "brave", x: 0, y: 73, width: 1470, height: 41),
            window(4142, "brave", x: 0, y: 33, width: 1470, height: 117),
            window(1893, "brave", x: 0, y: 114, width: 1470, height: 842),
        ]
        let apps = WindowCoverage.apps(in: windows, minFraction: 0.33, minVisibleArea: 40_000)
        #expect(apps.map { $0.appID } == ["brave"])
        #expect(apps.first?.isVisible == true)
        #expect(apps.first?.fraction == 1)
    }

    // MARK: What does and does not cover

    @Test func aSeeThroughWindowDoesNotCoverWhatIsBehindIt() {
        let apps = coverage([
            window(1, "ghost", x: 0, width: 735, alpha: 0.5),
            window(2, "editor", x: 0, width: 735),
        ])
        #expect(apps["editor"]?.fraction == 1)
        #expect(apps["editor"]?.isVisible == true)
    }

    @Test func aWindowWithNoKnownAppStillCoversOthersButIsNotListed() {
        let apps = WindowCoverage.apps(in: [
            window(1, nil, x: 0, width: 1470),
            window(2, "editor", x: 0, width: 735),
        ], minFraction: 0.33, minVisibleArea: 40_000)
        #expect(apps.map { $0.appID } == ["editor"])
        #expect(apps.first?.isVisible == false)
    }

    @Test func aTinyWindowIsNotAnAppInView() {
        // 150 x 150 is fully uncovered but far too small to count.
        let apps = coverage([window(1, "popup", x: 100, y: 100, width: 150, height: 150)])
        #expect(apps["popup"]?.fraction == 1)
        #expect(apps["popup"]?.isVisible == false)
    }

    @Test func anAppCountsByItsBestWindow() {
        // Brave's only window sits entirely under Terminal, so Brave is not visible. Give Brave a second window
        // out in the open and it is, even though its first window is still covered.
        let hidden = coverage([
            window(1, "terminal", x: 0, width: 735),
            window(2, "brave", x: 0, width: 735),
        ])
        #expect(hidden["brave"]?.isVisible == false)

        let shown = coverage([
            window(1, "terminal", x: 0, width: 735),
            window(2, "brave", x: 0, width: 735),
            window(3, "brave", x: 735, width: 735),
        ])
        #expect(shown["brave"]?.isVisible == true)
    }

    @Test func subtractingARectangleLeavesTheRest() {
        let whole = CGRect(x: 0, y: 0, width: 100, height: 100)
        #expect(WindowCoverage.subtract(whole, CGRect(x: 200, y: 200, width: 10, height: 10)) == [whole])
        #expect(WindowCoverage.subtract(whole, whole).isEmpty)

        let pieces = WindowCoverage.subtract(whole, CGRect(x: 25, y: 25, width: 50, height: 50))
        let area = pieces.reduce(0.0) { $0 + Double($1.width * $1.height) }
        #expect(area == 7_500)
    }

    // MARK: Deciding

    private let rules: [String: AppRule] = ["xcode": .show, "discord": .hide]

    private func decide(_ visible: [String], rules: [String: AppRule]? = nil, priority: RulePriority = .hideWins) -> VisibilityDecision {
        VisibilityRules.decide(visible: visible, rules: rules ?? self.rules, priority: priority, name: { $0.capitalized })
    }

    @Test func aShowAppAloneShowsTheWidget() {
        let decision = decide(["xcode"])
        #expect(decision.showWidget)
        #expect(decision.reason.contains("Xcode"))
    }

    @Test func aHideAppAloneHidesTheWidget() {
        let decision = decide(["discord"])
        #expect(!decision.showWidget)
        #expect(decision.reason.contains("Discord"))
    }

    @Test func thePriorityDecidesWhenBothKindsAreVisible() {
        #expect(!decide(["xcode", "discord"], priority: .hideWins).showWidget)
        #expect(decide(["xcode", "discord"], priority: .showWins).showWidget)
        #expect(decide(["discord", "xcode"], priority: .showWins).showWidget)   // the order does not matter
    }

    @Test func withShowAppsSetUpTheWidgetHidesWhenNoneIsVisible() {
        #expect(!decide([]).showWidget)
        #expect(!decide(["safari"]).showWidget)               // an app with no rule changes nothing
        #expect(!decide(["safari", "mail"], priority: .showWins).showWidget)
    }

    @Test func withOnlyHideAppsSetUpTheWidgetShowsUnlessOneIsVisible() {
        let onlyHide: [String: AppRule] = ["discord": .hide, "slack": .hide]
        #expect(decide([], rules: onlyHide).showWidget)
        #expect(decide(["safari"], rules: onlyHide).showWidget)
        #expect(!decide(["slack"], rules: onlyHide).showWidget)
        #expect(!decide(["safari", "discord"], rules: onlyHide).showWidget)
    }

    @Test func withNoRulesTheWidgetAlwaysShows() {
        #expect(decide([], rules: [:]).showWidget)
        #expect(decide(["discord"], rules: [:]).showWidget)
    }

    // MARK: Reading the window list

    @Test func theWindowListKeepsOnlyNormalWindowsOnTheDisplay() {
        let display = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let list: [[String: Any]] = [
            entry(id: 1, pid: 100, x: 0, y: 33, width: 735, height: 923),                  // Terminal: kept
            entry(id: 2, pid: 1, layer: 24, x: 0, y: 0, width: 1470, height: 33),          // menu bar: not a normal window
            entry(id: 3, pid: 200, x: 300, y: 100, width: 400, height: 400),               // Gitzy itself: left out
            entry(id: 4, pid: 101, x: 10, y: 100, width: 50, height: 50),                  // too small
            entry(id: 5, pid: 102, x: 2000, y: 33, width: 700, height: 500),               // on another display
            entry(id: 6, pid: 103, x: 1200, y: 33, width: 600, height: 500, alpha: 0.95),  // half off the display
        ]
        let reading = WindowSnapshot.samples(from: list, display: display, ownPID: 200, appID: { "app\($0)" })
        #expect(reading == .windows([
            WindowSample(id: 1, appID: "app100", bounds: CGRect(x: 0, y: 33, width: 735, height: 923), alpha: 1),
            WindowSample(id: 6, appID: "app103", bounds: CGRect(x: 1200, y: 33, width: 270, height: 500), alpha: 0.95),
        ]))
    }

    @Test func anAppWhoseBundleIdentifierIsUnknownIsKeptWithoutOne() {
        let display = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let list = [entry(id: 1, pid: 100, x: 0, y: 33, width: 735, height: 923)]
        let reading = WindowSnapshot.samples(from: list, display: display, ownPID: 200, appID: { _ in nil })
        #expect(reading == .windows([
            WindowSample(id: 1, appID: nil, bounds: CGRect(x: 0, y: 33, width: 735, height: 923), alpha: 1),
        ]))
    }

    @Test func aListWithNothingReadableIsReportedAsUnreadable() {
        let display = CGRect(x: 0, y: 0, width: 1470, height: 956)
        #expect(WindowSnapshot.samples(from: [], display: display, ownPID: 1, appID: { _ in nil }) == .unreadable)
        #expect(WindowSnapshot.samples(from: [["unrelated": 1]], display: display, ownPID: 1, appID: { _ in nil }) == .unreadable)
    }

    @Test func aDesktopWithNoNormalWindowsIsAnEmptyReadingNotAFailure() {
        let display = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let list = [entry(id: 2, pid: 1, layer: 24, x: 0, y: 0, width: 1470, height: 33)]   // only the menu bar
        #expect(WindowSnapshot.samples(from: list, display: display, ownPID: 200, appID: { _ in nil }) == .windows([]))
    }

    // MARK: Saved rules

    @Test func savedRulesAreReadBackAndBadEntriesAreDropped() {
        let saved: [String: Any] = ["a.app": "show", "b.app": "hide", "c.app": "maybe", "d.app": 5, "": "show"]
        #expect(AppRuleStorage.decode(saved) == ["a.app": .show, "b.app": .hide])
        #expect(AppRuleStorage.decode(nil).isEmpty)
        #expect(AppRuleStorage.decode(AppRuleStorage.encode(["x": .hide, "y": .show]) as [String: Any]) == ["x": .hide, "y": .show])
    }
}
