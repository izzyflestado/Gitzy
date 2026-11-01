import Foundation
import Testing
@testable import Gitzy

/// Only profile-picture addresses may ever be downloaded from. Every address here is made up.
nonisolated struct AvatarSourceTests {

    @Test func acceptsAGitHubPictureAddress() throws {
        let url = try #require(AvatarSource.validated("https://avatars.githubusercontent.com/u/12345?v=4&s=96"))
        #expect(url.host == "avatars.githubusercontent.com")
        #expect(url.absoluteString == "https://avatars.githubusercontent.com/u/12345?v=4&s=96")
    }

    @Test func acceptsTheNumberedFormsOlderRepliesUsed() {
        #expect(AvatarSource.validated("https://avatars0.githubusercontent.com/u/1") != nil)
        #expect(AvatarSource.validated("https://avatars3.githubusercontent.com/u/1") != nil)
    }

    @Test func hostNamesAreNotCaseSensitive() {
        #expect(AvatarSource.validated("https://AVATARS.GITHUBUSERCONTENT.COM/u/1") != nil)
        #expect(AvatarSource.validated("https://Avatars.GitHubUserContent.com/u/1") != nil)
    }

    @Test func refusesPlainHTTP() {
        #expect(AvatarSource.validated("http://avatars.githubusercontent.com/u/1") == nil)
    }

    @Test func refusesOtherHosts() {
        for text in [
            "https://github.com/octocat.png",
            "https://api.github.com/user",
            "https://example.com/u/1",
            "https://githubusercontent.com/u/1",
            "https://raw.githubusercontent.com/u/1",
            "https://avatarsx.githubusercontent.com/u/1",
            "https://evil.avatars.githubusercontent.com/u/1",
            "https://avatars.githubusercontent.com.example.com/u/1",
            "https://notavatars.githubusercontent.com/u/1"
        ] {
            #expect(AvatarSource.validated(text) == nil, "\(text)")
        }
    }

    @Test func refusesAddressesThatHideAnotherHost() {
        #expect(AvatarSource.validated("https://avatars.githubusercontent.com@example.com/u/1") == nil)
        #expect(AvatarSource.validated("https://user:pass@avatars.githubusercontent.com/u/1") == nil)
        #expect(AvatarSource.validated("https://avatars.githubusercontent.com:8443/u/1") == nil)
    }

    @Test func refusesNothingAndNonsense() {
        #expect(AvatarSource.validated(nil) == nil)
        #expect(AvatarSource.validated("") == nil)
        #expect(AvatarSource.validated("not an address") == nil)
        #expect(AvatarSource.validated("file:///etc/passwd") == nil)
        #expect(AvatarSource.validated("avatars.githubusercontent.com/u/1") == nil)   // no scheme
    }

    @Test func hostCheckOnItsOwn() {
        #expect(AvatarSource.isAvatarHost("avatars.githubusercontent.com"))
        #expect(!AvatarSource.isAvatarHost("avatars.githubusercontent.org"))
        #expect(!AvatarSource.isAvatarHost(""))
    }
}
