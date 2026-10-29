import Foundation
import Testing
@testable import Gitzy

/// The sample "tokens" here are made-up letters and digits, never anything that resembles a real token.
/// Every test works in a throwaway folder, so the real token file is never touched.
nonisolated struct TokenFileTests {
    private let sample = String(repeating: "a1B2", count: 10)
    private let other = String(repeating: "z9Y8", count: 10)

    /// Runs `body` with a TokenFile whose folder does not exist yet, inside a temp folder that lives until it finishes.
    private func withTokenFile(_ body: (TokenFile, URL) throws -> Void) throws {
        let temp = try TempFolder()
        let folder = temp.root.appendingPathComponent("Gitzy", isDirectory: true)
        try body(TokenFile(directory: folder), folder)
        withExtendedLifetime(temp) {}
    }

    private func permissions(of url: URL) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }

    // MARK: Saving and loading

    @Test func aSavedTokenComesBack() throws {
        try withTokenFile { file, _ in
            try file.save(token: sample)
            #expect(file.load() == .found(sample))
        }
    }

    @Test func nothingSavedMeansMissing() throws {
        try withTokenFile { file, _ in
            #expect(file.load() == .missing)
        }
    }

    @Test func savingAgainReplacesTheToken() throws {
        try withTokenFile { file, _ in
            try file.save(token: sample)
            try file.save(token: other)
            #expect(file.load() == .found(other))
        }
    }

    @Test func aSaveLeavesNoTemporaryFileBehind() throws {
        try withTokenFile { file, folder in
            try file.save(token: sample)
            try file.save(token: other)
            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            #expect(names == [TokenFile.fileName])
        }
    }

    // MARK: Privacy

    @Test func theFileAndItsFolderArePrivate() throws {
        try withTokenFile { file, folder in
            try file.save(token: sample)
            #expect(permissions(of: file.fileURL) == 0o600)
            #expect(permissions(of: folder) == 0o700)
        }
    }

    @Test func anExistingOpenFolderIsTightened() throws {
        try withTokenFile { file, folder in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
            try file.save(token: sample)
            #expect(permissions(of: folder) == 0o700)
        }
    }

    // MARK: Deleting

    @Test func deletingRemovesTheToken() throws {
        try withTokenFile { file, _ in
            try file.save(token: sample)
            #expect(file.delete())
            #expect(file.load() == .missing)
            #expect(!FileManager.default.fileExists(atPath: file.fileURL.path))
        }
    }

    @Test func deletingWhenNothingIsSavedIsFine() throws {
        try withTokenFile { file, _ in
            #expect(file.delete())
        }
    }

    // MARK: Odd files

    @Test func surroundingWhitespaceIsIgnored() throws {
        try withTokenFile { file, folder in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "  \(sample)\n".write(to: file.fileURL, atomically: true, encoding: .utf8)
            #expect(file.load() == .found(sample))
        }
    }

    @Test func anEmptyFileCountsAsMissing() throws {
        try withTokenFile { file, folder in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try "\n".write(to: file.fileURL, atomically: true, encoding: .utf8)
            #expect(file.load() == .missing)
        }
    }

    @Test func aFileThatCannotBeReadIsNotTheSameAsMissing() throws {
        try withTokenFile { file, _ in
            try file.save(token: sample)
            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file.fileURL.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.fileURL.path) }
            #expect(file.load() == .unreadable)
        }
    }

    // MARK: Failures

    @Test func aFolderThatCannotBeCreatedGivesAReadableFailure() throws {
        let temp = try TempFolder()
        try temp.write("a file, not a folder", to: "blocker")
        let file = TokenFile(directory: temp.root.appendingPathComponent("blocker/Gitzy", isDirectory: true))
        do {
            try file.save(token: sample)
            Issue.record("Saving should have failed.")
        } catch let failure as TokenFile.Failure {
            #expect(!failure.message.isEmpty)
            #expect(!failure.message.contains(sample))
        } catch {
            Issue.record("Saving failed with an unexpected kind of error.")
        }
    }

    @Test func theStandardLocationIsInsideApplicationSupport() {
        let path = TokenFile.standard.fileURL.path
        #expect(path.hasSuffix("/Library/Application Support/Gitzy/github-token"))
    }

    // MARK: StoredToken

    @Test func onlyAFoundTokenHasText() {
        #expect(TokenFile.StoredToken.found(sample).token == sample)
        #expect(TokenFile.StoredToken.missing.token == nil)
        #expect(TokenFile.StoredToken.unreadable.token == nil)
    }
}
