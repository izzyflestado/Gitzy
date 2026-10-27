import Foundation
import Testing
@testable import Gitzy

/// The sample "tokens" here are made-up letters and digits, never anything that resembles a real token.
nonisolated struct TokenChecksTests {
    private let sample = String(repeating: "a1B2", count: 10)   // 40 characters

    // MARK: TokenFormat

    @Test func acceptsAPlainToken() {
        #expect(TokenFormat.cleaned(sample) == sample)
    }

    @Test func trimsSpacesAndLineBreaksAroundIt() {
        #expect(TokenFormat.cleaned("  \(sample)\n") == sample)
        #expect(TokenFormat.cleaned("\t\(sample)\r\n") == sample)
    }

    @Test func acceptsUnderscoresAndHyphens() {
        let withSeparators = "abc_" + sample + "-xyz"
        #expect(TokenFormat.cleaned(withSeparators) == withSeparators)
    }

    @Test func rejectsTextThatCannotBeAToken() {
        #expect(TokenFormat.cleaned("") == nil)
        #expect(TokenFormat.cleaned("   ") == nil)
        #expect(TokenFormat.cleaned("short") == nil)
        #expect(TokenFormat.cleaned(String(repeating: "a", count: 19)) == nil)
        #expect(TokenFormat.cleaned(String(repeating: "a", count: 256)) == nil)
    }

    @Test func rejectsInnerWhitespaceAndOddCharacters() {
        #expect(TokenFormat.cleaned(sample + " " + sample) == nil)
        #expect(TokenFormat.cleaned(sample + "\n" + sample) == nil)
        #expect(TokenFormat.cleaned(sample + ":") == nil)
        #expect(TokenFormat.cleaned("Authorization: " + sample) == nil)
        #expect(TokenFormat.cleaned(sample + "é") == nil)
        #expect(TokenFormat.cleaned(sample + "\u{0}") == nil)
    }

    // MARK: ScopeReport

    @Test func exactlyReadUserIsFine() {
        let report = ScopeReport(scopes: ["read:user"])
        #expect(report.known)
        #expect(report.hasReadUser)
        #expect(report.extras.isEmpty)
        #expect(report.warning == nil)
    }

    @Test func unknownScopesAreSaidOutLoud() {
        let report = ScopeReport(scopes: nil)
        #expect(!report.known)
        #expect(report.warning?.contains("did not report") == true)
    }

    @Test func noScopesAtAll() {
        let report = ScopeReport(scopes: [])
        #expect(report.known)
        #expect(!report.hasReadUser)
        #expect(report.warning?.contains("does not have read:user") == true)
    }

    @Test func extraScopesAreCalledOut() {
        let report = ScopeReport(scopes: ["read:user", "repo"])
        #expect(report.hasReadUser)
        #expect(report.extras == ["repo"])
        #expect(report.warning?.contains("more than Gitzy needs") == true)
        #expect(report.warning?.contains("repo") == true)
    }

    @Test func theBroaderUserScopeCountsAsExtra() {
        let report = ScopeReport(scopes: ["user"])
        #expect(report.hasReadUser)
        #expect(report.extras == ["user"])
        #expect(report.warning != nil)
    }

    @Test func wrongScopesOnly() {
        let report = ScopeReport(scopes: ["repo", "gist"])
        #expect(!report.hasReadUser)
        #expect(report.warning?.contains("repo, gist") == true)
        #expect(report.warning?.contains("Replace it") == true)
    }
}
