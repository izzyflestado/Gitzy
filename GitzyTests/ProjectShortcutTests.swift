import Foundation
import Testing
@testable import Gitzy

struct ProjectShortcutTests {

    private let optionShift = KeyShortcut.option | KeyShortcut.shift
    /// The key codes of 1 2 3 4 5 6 7 8 9 0 on a Mac keyboard. They are not in order.
    private let numberKeyCodes: [UInt32] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]

    // MARK: Defaults

    @Test func defaultsAreOptionShiftBacktickAndOptionShiftOne() {
        #expect(ShortcutAction.openOnGitHub.defaultShortcut == KeyShortcut(keyCode: 0x32, modifiers: optionShift))
        #expect(ShortcutAction.openProjectByNumber.defaultShortcut == KeyShortcut(keyCode: 0x12, modifiers: optionShift))
    }

    @Test func displayNames() {
        let github = ShortcutAction.openOnGitHub
        let numbered = ShortcutAction.openProjectByNumber
        #expect(github.display(github.defaultShortcut) == "⌥⇧`")
        #expect(numbered.display(numbered.defaultShortcut) == "⌥⇧1–0")
        // The other actions are written the usual way.
        #expect(ShortcutAction.openInFinder.display(ShortcutAction.openInFinder.defaultShortcut) == "⌥⇧]")
    }

    @Test func everyDefaultIsAllowed() {
        for action in ShortcutAction.allCases {
            #expect(action.defaultShortcut.isAllowed)
        }
    }

    @Test func noTwoDefaultKeyCombinationsAreTheSame() {
        var seen = Set<KeyShortcut>()
        for action in ShortcutAction.allCases {
            for keys in action.keys(for: action.defaultShortcut) {
                let isNew = seen.insert(keys).inserted
                #expect(isNew, "\(keys.display) is used twice")
            }
        }
    }

    // MARK: The numbered action

    @Test func numberedActionCoversTheTenNumberKeysInOrder() {
        let numbered = ShortcutAction.openProjectByNumber
        let keys = numbered.keys(for: numbered.defaultShortcut)
        #expect(keys.map(\.keyCode) == numberKeyCodes)
        // 1 to 9, then 0 for the tenth project.
        #expect(keys.map(\.display) == ["⌥⇧1", "⌥⇧2", "⌥⇧3", "⌥⇧4", "⌥⇧5", "⌥⇧6", "⌥⇧7", "⌥⇧8", "⌥⇧9", "⌥⇧0"])
        #expect(keys.allSatisfy { $0.modifiers == optionShift })
    }

    @Test func otherActionsAreExactlyOneKey() {
        for action in ShortcutAction.allCases where action != .openProjectByNumber {
            #expect(action.keys(for: action.defaultShortcut) == [action.defaultShortcut])
        }
    }

    @Test func numberedActionKeepsOnlyTheTypedModifiers() {
        let numbered = ShortcutAction.openProjectByNumber
        let typed = KeyShortcut(keyCode: 0x0C, modifiers: KeyShortcut.control | KeyShortcut.command)   // ⌃⌘Q
        #expect(numbered.normalized(typed) == KeyShortcut(keyCode: 0x12, modifiers: KeyShortcut.control | KeyShortcut.command))
        // Every other action keeps exactly what was typed.
        #expect(ShortcutAction.openInFinder.normalized(typed) == typed)
    }

    // MARK: Saved settings

    @Test func settingsSavedBeforeTheNewActionsStillDecode() throws {
        let changed = KeyShortcut(keyCode: 0x00, modifiers: optionShift)
        let old = ["openInFinder": changed]
        let decoded = ShortcutBindings.decode(try JSONEncoder().encode(old))

        #expect(decoded[.openInFinder] == changed)
        #expect(decoded[.openOnGitHub] == ShortcutAction.openOnGitHub.defaultShortcut)
        #expect(decoded[.openProjectByNumber] == ShortcutAction.openProjectByNumber.defaultShortcut)
        #expect(decoded.count == ShortcutAction.allCases.count)
    }

    @Test func savedNumberedShortcutAlwaysEndsOnKeyOne() throws {
        let modifiers = KeyShortcut.control | KeyShortcut.option
        let saved = ["openProjectByNumber": KeyShortcut(keyCode: 0x0C, modifiers: modifiers)]
        let decoded = ShortcutBindings.decode(try JSONEncoder().encode(saved))
        #expect(decoded[.openProjectByNumber] == KeyShortcut(keyCode: 0x12, modifiers: modifiers))
    }

    // MARK: Place in the list

    @Test func placesCountFromOneAtTheTopAndTheZeroKeyIsTen() {
        let list = (1...10).map { "project \($0)" }
        #expect(ProjectPosition.item(at: 1, in: list) == "project 1")
        #expect(ProjectPosition.item(at: 9, in: list) == "project 9")
        #expect(ProjectPosition.item(at: 10, in: list) == "project 10")
    }

    @Test func placeBeyondTheListIsNil() {
        let three = ["first", "second", "third"]
        #expect(ProjectPosition.item(at: 4, in: three) == nil)
        #expect(ProjectPosition.item(at: 10, in: three) == nil)
        #expect(ProjectPosition.item(at: 11, in: (1...10).map { "p\($0)" }) == nil)
        #expect(ProjectPosition.item(at: 0, in: three) == nil)
        #expect(ProjectPosition.item(at: -1, in: three) == nil)
        #expect(ProjectPosition.item(at: 1, in: [String]()) == nil)
    }
}
