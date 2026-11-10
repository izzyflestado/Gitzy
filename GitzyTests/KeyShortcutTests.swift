import Foundation
import Testing
@testable import Gitzy

nonisolated struct KeyShortcutTests {

    // MARK: The defaults

    @Test func defaultKeysAreOptionShiftBracketBracketBackslash() {
        #expect(ShortcutAction.openInFinder.defaultShortcut.display == "⌥⇧]")
        #expect(ShortcutAction.openInTerminal.defaultShortcut.display == "⌥⇧[")
        #expect(ShortcutAction.openInIDE.defaultShortcut.display == "⌥⇧\\")
    }

    @Test func defaultsAreAllowedAndDifferent() {
        let defaults = ShortcutAction.allCases.map(\.defaultShortcut)
        #expect(defaults.allSatisfy(\.isAllowed))
        #expect(Set(defaults).count == defaults.count)
    }

    @Test func everyActionHasATitle() {
        #expect(ShortcutAction.openInFinder.title == "Open in Finder")
        #expect(ShortcutAction.openInTerminal.title == "Open in Terminal")
        #expect(ShortcutAction.openInIDE.title == "Open in default IDE")
    }

    // MARK: Showing keys

    @Test func modifiersAreWrittenInTheUsualOrder() {
        let all = KeyShortcut.command | KeyShortcut.shift | KeyShortcut.option | KeyShortcut.control
        #expect(KeyShortcut(keyCode: 0x00, modifiers: all).display == "⌃⌥⇧⌘A")
        #expect(KeyShortcut(keyCode: 0x24, modifiers: KeyShortcut.command).display == "⌘↩")
        #expect(KeyShortcut(keyCode: 0x31, modifiers: KeyShortcut.control | KeyShortcut.option).display == "⌃⌥Space")
    }

    @Test func unknownKeysShowTheirNumber() {
        #expect(KeyShortcut(keyCode: 0x7F, modifiers: KeyShortcut.command).display == "⌘Key 127")
    }

    @Test func commonKeysHaveNames() {
        let option = KeyShortcut.option
        #expect(KeyShortcut(keyCode: 0x33, modifiers: option).display == "⌥⌫")
        #expect(KeyShortcut(keyCode: 0x7B, modifiers: option).display == "⌥←")
        #expect(KeyShortcut(keyCode: 0x7E, modifiers: option).display == "⌥↑")
        #expect(KeyShortcut(keyCode: 0x7A, modifiers: option).display == "⌥F1")
    }
    }

    // MARK: What is allowed

    @Test func aGlobalShortcutNeedsCommandOptionOrControl() {
        #expect(KeyShortcut(keyCode: 0x21, modifiers: KeyShortcut.option).isAllowed)
        #expect(KeyShortcut(keyCode: 0x21, modifiers: KeyShortcut.command).isAllowed)
        #expect(KeyShortcut(keyCode: 0x21, modifiers: KeyShortcut.control | KeyShortcut.shift).isAllowed)
        #expect(!KeyShortcut(keyCode: 0x21, modifiers: 0).isAllowed)
        #expect(!KeyShortcut(keyCode: 0x21, modifiers: KeyShortcut.shift).isAllowed)
    }

    @Test func unknownModifierBitsAreNotAllowed() {
        #expect(!KeyShortcut(keyCode: 0x21, modifiers: KeyShortcut.option | 0x0400).isAllowed)
    }

    // MARK: Saving and loading

    @Test func noSavedDataGivesTheDefaults() {
        #expect(ShortcutBindings.decode(nil) == ShortcutBindings.defaults)
    }

    @Test func savedShortcutsComeBack() throws {
        var bindings = ShortcutBindings.defaults
        bindings[.openInTerminal] = KeyShortcut(keyCode: 0x11, modifiers: KeyShortcut.command | KeyShortcut.option)
        let data = try #require(ShortcutBindings.encode(bindings))
        #expect(ShortcutBindings.decode(data) == bindings)
    }

    @Test func garbageGivesTheDefaults() {
        #expect(ShortcutBindings.decode(Data("not json".utf8)) == ShortcutBindings.defaults)
        #expect(ShortcutBindings.decode(Data()) == ShortcutBindings.defaults)
        #expect(ShortcutBindings.decode(Data("[1, 2, 3]".utf8)) == ShortcutBindings.defaults)
    }

    @Test func aSavedShortcutThatIsNotAllowedIsReplacedByTheDefault() throws {
        var bindings = ShortcutBindings.defaults
        bindings[.openInFinder] = KeyShortcut(keyCode: 0x00, modifiers: 0)   // a bare "A" would take over typing
        bindings[.openInIDE] = KeyShortcut(keyCode: 0x08, modifiers: KeyShortcut.command | KeyShortcut.shift)
        let data = try #require(ShortcutBindings.encode(bindings))

        let loaded = ShortcutBindings.decode(data)
        #expect(loaded[.openInFinder] == ShortcutAction.openInFinder.defaultShortcut)
        #expect(loaded[.openInIDE] == bindings[.openInIDE])
    }

    @Test func missingAndUnknownActionsAreHandled() throws {
        // Only one action saved, and one name that does not exist (an older or newer version, say).
        let json = """
        {"openInTerminal": {"keyCode": 17, "modifiers": 2304}, "somethingElse": {"keyCode": 1, "modifiers": 256}}
        """
        let loaded = ShortcutBindings.decode(Data(json.utf8))
        #expect(loaded[.openInTerminal] == KeyShortcut(keyCode: 17, modifiers: 2304))
        #expect(loaded[.openInFinder] == ShortcutAction.openInFinder.defaultShortcut)
        #expect(loaded[.openInIDE] == ShortcutAction.openInIDE.defaultShortcut)
        #expect(loaded.count == ShortcutAction.allCases.count)
    }
}
