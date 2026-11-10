import Foundation

/// How an action turns into actual key combinations. Most actions are one combination. "Open project 1 to 10"
/// is one setting (the modifier keys) that covers the ten number keys: 1 to 9, then 0 for the tenth project.
nonisolated extension ShortcutAction {

    /// The number keys in the order of the projects they open: 1 to 9, then 0 for project 10.
    /// The key codes are not in order on a Mac keyboard (5 and 6 are swapped, and 7, 8, 9, 0 are scattered).
    static let numberKeyCodes: [UInt32] = [0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D]

    /// Every key combination that triggers this action. For the numbered action, the place in this list
    /// is the project's place in the Projects list, minus one.
    func keys(for shortcut: KeyShortcut) -> [KeyShortcut] {
        switch self {
        case .openProjectByNumber:
            return Self.numberKeyCodes.map { KeyShortcut(keyCode: $0, modifiers: shortcut.modifiers) }
        default:
            return [shortcut]
        }
    }

    /// The numbered action keeps only the modifier keys that were typed: its keys are always 1 to 9 and 0.
    func normalized(_ shortcut: KeyShortcut) -> KeyShortcut {
        switch self {
        case .openProjectByNumber:
            return KeyShortcut(keyCode: Self.numberKeyCodes[0], modifiers: shortcut.modifiers)
        default:
            return shortcut
        }
    }

    /// How the keys are written in Settings: "⌥⇧1–0" for the numbered action, the plain combination otherwise.
    func display(_ shortcut: KeyShortcut) -> String {
        switch self {
        case .openProjectByNumber:
            return shortcut.display + "–0"
        default:
            return shortcut.display
        }
    }
}

/// "Project 1" is the top of the Projects list. The list handed in must already be in the order the person sees.
nonisolated enum ProjectPosition {

    /// The item at a place counted from 1 (the 0 key is place 10), or nil when the list is shorter than that
    /// or the number is below 1.
    static func item<Item>(at number: Int, in list: [Item]) -> Item? {
        guard number >= 1, number <= list.count else { return nil }
        return list[number - 1]
    }
}
