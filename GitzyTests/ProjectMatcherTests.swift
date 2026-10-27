import Testing
@testable import Gitzy

nonisolated struct ProjectMatcherTests {
    private let projects = ["/Users/me/app", "/Users/me/other"]

    @Test func theProjectFolderItself() {
        #expect(ProjectMatcher.match(path: "/Users/me/app", in: projects) == "/Users/me/app")
    }

    @Test func anXcodeProjectInsideAProject() {
        #expect(ProjectMatcher.match(path: "/Users/me/app/App.xcodeproj", in: projects) == "/Users/me/app")
        #expect(ProjectMatcher.match(path: "/Users/me/app/ios/App.xcworkspace", in: projects) == "/Users/me/app")
    }

    @Test func theDeepestProjectWins() {
        let nested = ["/Users/me/mono", "/Users/me/mono/apps/web"]
        #expect(ProjectMatcher.match(path: "/Users/me/mono/apps/web/Web.xcodeproj", in: nested) == "/Users/me/mono/apps/web")
        #expect(ProjectMatcher.match(path: "/Users/me/mono/tools/Tool.xcodeproj", in: nested) == "/Users/me/mono")
    }

    @Test func aFolderWithTheSamePrefixIsNotTheSameProject() {
        #expect(ProjectMatcher.match(path: "/Users/me/app-two/App.xcodeproj", in: projects) == nil)
    }

    @Test func nothingMatchesAnUnsavedProject() {
        #expect(ProjectMatcher.match(path: "/Users/me/elsewhere/Thing.xcodeproj", in: projects) == nil)
        #expect(ProjectMatcher.match(path: "/Users/me/app", in: []) == nil)
    }

    @Test func aParentOfAProjectIsNotAMatch() {
        #expect(ProjectMatcher.match(path: "/Users/me", in: projects) == nil)
    }

    @Test func aTrailingSlashDoesNotMatter() {
        #expect(ProjectMatcher.match(path: "/Users/me/app/App.xcodeproj", in: ["/Users/me/app/"]) == "/Users/me/app/")
    }
}
