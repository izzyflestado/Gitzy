import Foundation

/// How an action turns into actual key combinations. Most actions are one combination. "Open project 1, 2 or 3"
/// is one setting (the modifier keys) that covers the three number keys 1, 2 and 3.
nonisolated extension ShortcutAction {

    /// 1, 2 and 3 are side by side on the keyboard: key codes 0x12, 0x13, 0x14.
    static let firstNumberKeyCode: UInt32 = 0x12
    static let numberKeyCount = 3

    /// Every key combination that triggers this action. For the numbered action, the place in this list
    /// is the project number minus one.
    func keys(for shortcut: KeyShortcut) -> [KeyShortcut] {
        switch self {
        case .openProjectByNumber:
            return (0..<Self.numberKeyCount).map {
                KeyShortcut(keyCode: Self.firstNumberKeyCode + UInt32($0), modifiers: shortcut.modifiers)
            }
        default:
            return [shortcut]
        }
    }

    /// The numbered action keeps only the modifier keys that were typed: its keys are always 1, 2 and 3.
    func normalized(_ shortcut: KeyShortcut) -> KeyShortcut {
        switch self {
        case .openProjectByNumber:
            return KeyShortcut(keyCode: Self.firstNumberKeyCode, modifiers: shortcut.modifiers)
        default:
            return shortcut
        }
    }

    /// How the keys are written in Settings: "⌥⇧1/2/3" for the numbered action, the plain combination otherwise.
    func display(_ shortcut: KeyShortcut) -> String {
        switch self {
        case .openProjectByNumber:
            return shortcut.display + "/2/3"
        default:
            return shortcut.display
        }
    }
}

/// "Project 1" is the top of the Projects list. The list handed in must already be in the order the person sees.
nonisolated enum ProjectPosition {

    /// The item at a place counted from 1, or nil when the list is shorter than that (or the number is below 1).
    static func item<Item>(at number: Int, in list: [Item]) -> Item? {
        guard number >= 1, number <= list.count else { return nil }
        return list[number - 1]
    }
}
