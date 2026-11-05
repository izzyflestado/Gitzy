import Carbon.HIToolbox

/// What happened when a combination was registered.
enum HotKeyRegistration: Equatable {
    case registered
    /// Another app, or macOS itself, already owns these keys.
    case alreadyTaken
    /// The system refused for some other reason. The number is its error code.
    case failed(Int)
}

/// Registers shortcuts that work in every app, whether or not Gitzy is in front.
///
/// This uses Carbon's RegisterEventHotKey, which is the one system-wide shortcut mechanism that needs no permission
/// (no Accessibility, no Input Monitoring) and sees only the exact keys that were registered, never other typing.
/// The catch is that a registered combination belongs to Gitzy alone, so no other app receives it.
/// A combination another app has already taken is refused, and `register` says so.
final class GlobalHotKeys {
    static let shared = GlobalHotKeys()

    private struct Registered {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private var registered: [UInt32: Registered] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    private init() {}

    /// `.registered` when the shortcut is now active.
    func register(_ shortcut: KeyShortcut, action: @escaping () -> Void) -> HotKeyRegistration {
        installHandlerIfNeeded()

        let id = nextID
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            EventHotKeyID(signature: hotKeySignature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr else {
            return status == OSStatus(eventHotKeyExistsErr) ? .alreadyTaken : .failed(Int(status))
        }
        guard let ref else { return .failed(Int(paramErr)) }

        nextID += 1
        registered[id] = Registered(ref: ref, action: action)
        return .registered
    }

    /// Gives every registered combination back, so other apps can use them again.
    func unregisterAll() {
        for entry in registered.values { UnregisterEventHotKey(entry.ref) }
        registered.removeAll()
    }

    fileprivate func fire(id: UInt32) {
        registered[id]?.action()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyPressed, 1, &spec, nil, &handler)
    }
}

/// Four letters ("GITY") that mark these shortcuts as Gitzy's. Nonisolated, because the system's callback below
/// is not running on the main actor and reads it.
private nonisolated let hotKeySignature: OSType = 0x47495459

/// Called by the system on the main thread whenever one of Gitzy's registered combinations is pressed.
/// A plain function with no captured state, because that is what the system's callback type requires.
private nonisolated func hotKeyPressed(
    _ next: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr, hotKeyID.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }

    let id = hotKeyID.id
    Task { @MainActor in GlobalHotKeys.shared.fire(id: id) }
    return noErr
}
