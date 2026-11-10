import Foundation

/// One key combination, in the form macOS global shortcuts use: a physical key and a set of modifier keys.
///
/// `keyCode` is the key's position on the keyboard (the same numbers as the `kVK_ANSI_...` constants), so a shortcut
/// stays on the same physical key whatever the keyboard layout is. `modifiers` uses the Carbon flag values.
/// Plain numbers are used on purpose, so this type needs no system framework and is easy to test.
nonisolated struct KeyShortcut: Codable, Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let command: UInt32 = 0x0100   // cmdKey
    static let shift: UInt32 = 0x0200     // shiftKey
    static let option: UInt32 = 0x0800    // optionKey
    static let control: UInt32 = 0x1000   // controlKey

    private static let everyModifier: UInt32 = command | shift | option | control

    /// A global shortcut must include ⌘, ⌥ or ⌃. Shift alone (or nothing) would take over ordinary typing in every app.
    var isAllowed: Bool {
        modifiers & (Self.command | Self.option | Self.control) != 0
            && modifiers & ~Self.everyModifier == 0
    }

    /// How it is written in menus: modifiers in the usual order (⌃ ⌥ ⇧ ⌘), then the key. For example "⌥⇧[".
    var display: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "Key \(keyCode)")
    }

    /// Names for the keys of a Mac keyboard: the main block, Delete, the arrows, Home/End/Page keys, F1 to F20 and the
    /// number pad. A key that is not listed here shows as "Key <number>".
    private static let keyNames: [UInt32: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0A: "§", 0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T",
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-",
        0x1C: "8", 0x1D: "0", 0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P", 0x24: "↩",
        0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";", 0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M",
        0x2F: ".", 0x30: "⇥", 0x31: "Space", 0x32: "`", 0x33: "⌫", 0x35: "⎋",

        // Number pad
        0x41: "Num .", 0x43: "Num *", 0x45: "Num +", 0x47: "Num Clear", 0x4B: "Num /", 0x4C: "⌤", 0x4E: "Num -",
        0x51: "Num =", 0x52: "Num 0", 0x53: "Num 1", 0x54: "Num 2", 0x55: "Num 3", 0x56: "Num 4", 0x57: "Num 5",
        0x58: "Num 6", 0x59: "Num 7", 0x5B: "Num 8", 0x5C: "Num 9",

        // Function keys
        0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8", 0x65: "F9",
        0x6D: "F10", 0x67: "F11", 0x6F: "F12", 0x69: "F13", 0x6B: "F14", 0x71: "F15", 0x6A: "F16", 0x40: "F17",
        0x4F: "F18", 0x50: "F19", 0x5A: "F20",

        // Navigation
        0x72: "Help", 0x73: "↖", 0x74: "⇞", 0x75: "⌦", 0x77: "↘", 0x79: "⇟",
        0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑",
    ]
}

/// The things a shortcut can do. The first three act on the repository that is open in the editor in front;
/// "Open Gitzy menu" opens Gitzy's own menu bar window.
nonisolated enum ShortcutAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case openInFinder
    case openInTerminal
    case openInIDE
    case openMenu

    var id: String { rawValue }

    var title: String {
        switch self {
        case .openInFinder: return "Open in Finder"
        case .openInTerminal: return "Open in Terminal"
        case .openInIDE: return "Open in default IDE"
        case .openMenu: return "Open Gitzy menu"
        }
    }

    /// All of them are ⌥⇧ with a key: [ ] \ are three neighbouring keys, and Return opens the menu.
    var defaultShortcut: KeyShortcut {
        let modifiers = KeyShortcut.option | KeyShortcut.shift
        switch self {
        case .openInFinder: return KeyShortcut(keyCode: 0x1E, modifiers: modifiers)     // ]
        case .openInTerminal: return KeyShortcut(keyCode: 0x21, modifiers: modifiers)   // [
        case .openInIDE: return KeyShortcut(keyCode: 0x2A, modifiers: modifiers)        // \
        case .openMenu: return KeyShortcut(keyCode: 0x24, modifiers: modifiers)   // Return
        }
    }
}

/// Turns the saved shortcuts into data and back. Anything that is missing, unreadable or not allowed falls back
/// to the default for that action, so a damaged setting can never leave an action without a working shortcut.
nonisolated enum ShortcutBindings {

    static var defaults: [ShortcutAction: KeyShortcut] {
        Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
    }

    static func decode(_ data: Data?) -> [ShortcutAction: KeyShortcut] {
        var result = defaults
        guard let data, let saved = try? JSONDecoder().decode([String: KeyShortcut].self, from: data) else {
            return result
        }
        for action in ShortcutAction.allCases {
            if let shortcut = saved[action.rawValue], shortcut.isAllowed {
                result[action] = shortcut
            }
        }
        return result
    }

    static func encode(_ bindings: [ShortcutAction: KeyShortcut]) -> Data? {
        var named: [String: KeyShortcut] = [:]
        for (action, shortcut) in bindings { named[action.rawValue] = shortcut }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try? encoder.encode(named)
    }
}
