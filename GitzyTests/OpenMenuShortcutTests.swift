import Foundation
import Testing
@testable import Gitzy

/// The "Open Gitzy menu" shortcut: its default keys, its title, and that old saved settings still load.
nonisolated struct OpenMenuShortcutTests {

    @Test func theMenuShortcutDefaultsToOptionShiftReturn() {
        let expected = KeyShortcut(keyCode: 0x24, modifiers: KeyShortcut.option | KeyShortcut.shift)
        #expect(ShortcutAction.openMenu.defaultShortcut == expected)
        #expect(ShortcutAction.openMenu.defaultShortcut.display == "⌥⇧↩")
    }

    @Test func theMenuShortcutHasATitle() {
        #expect(ShortcutAction.openMenu.title == "Open Gitzy menu")
    }

    @Test func theMenuShortcutIsAllowedAndDiffersFromTheOthers() {
        let menu = ShortcutAction.openMenu.defaultShortcut
        #expect(menu.isAllowed)
        for other in ShortcutAction.allCases where other != .openMenu {
            #expect(other.defaultShortcut != menu)
        }
    }

    @Test func aChangedMenuShortcutIsSavedAndComesBack() throws {
        var bindings = ShortcutBindings.defaults
        bindings[.openMenu] = KeyShortcut(keyCode: 0x31, modifiers: KeyShortcut.control | KeyShortcut.option)   // ⌃⌥Space
        let data = try #require(ShortcutBindings.encode(bindings))
        #expect(ShortcutBindings.decode(data)[.openMenu] == bindings[.openMenu])
    }

    @Test func settingsSavedBeforeTheMenuShortcutExistedStillLoad() {
        // Only the three older actions were saved. The menu shortcut falls back to its default.
        let json = """
        {"openInFinder": {"keyCode": 17, "modifiers": 2304}, "openInTerminal": {"keyCode": 8, "modifiers": 2304}}
        """
        let loaded = ShortcutBindings.decode(Data(json.utf8))
        #expect(loaded[.openInFinder] == KeyShortcut(keyCode: 17, modifiers: 2304))
        #expect(loaded[.openMenu] == ShortcutAction.openMenu.defaultShortcut)
        #expect(loaded.count == ShortcutAction.allCases.count)
    }
}
