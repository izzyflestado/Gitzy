import AppKit
import SwiftUI

/// The keyboard shortcuts part of Settings: an on/off switch, the keys for each action, and Restore Defaults.
///
/// To change a shortcut: click its keys, press the new combination (it shows as you type), then press Return to keep
/// it. Esc cancels. While one is being recorded the global shortcuts are switched off, so pressing the keys of an
/// existing shortcut does not trigger it.
struct ShortcutsSettingsSection: View {
    let controller: ShortcutController

    /// The action being recorded, if any.
    @State private var recording: ShortcutAction?
    /// The combination typed so far, shown in the key cap until Return keeps it.
    @State private var pending: KeyShortcut?
    /// Why the last attempt was refused.
    @State private var message: String?
    @State private var monitor: Any?

    var body: some View {
        Section {
            Toggle("Use global shortcuts", isOn: enabledBinding)
                // Recording ends whenever this window stops being the one typed into, or closes, so the global
                // shortcuts always come back (they are off while recording).
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
                    stopRecording()
                }
                .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in
                    stopRecording()
                }
                .onDisappear { stopRecording() }

            ForEach(ShortcutAction.allCases) { action in
                LabeledContent(action.title) {
                    keyCap(for: action)
                }
                if recording == action {
                    note(recordingHint, isProblem: message != nil)
                } else if let problem = controller.problems[action] {
                    note(problem, isProblem: true)
                }
            }
        } header: {
            HStack {
                Text("Keyboard shortcuts")
                Spacer()
                Button("Restore Defaults", action: restoreDefaults)
                    .controlSize(.small)
                    .disabled(controller.shortcuts == ShortcutBindings.defaults)
            }
        }
    }

    // MARK: Pieces

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { controller.isEnabled },
            set: {
                stopRecording()
                controller.setEnabled($0)
            }
        )
    }

    private func keyCap(for action: ShortcutAction) -> some View {
        let isRecording = recording == action
        let text = isRecording
            ? (pending.map { action.display($0) } ?? "Type shortcut…")
            : action.display(controller.shortcut(for: action))

        return Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording(action)
            }
        } label: {
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(capColor(isRecording: isRecording))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(minWidth: 56)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isRecording ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(!action.isEditable)
        .opacity(action.isEditable ? 1 : 0.45)
        .help(action.isEditable
              ? (isRecording ? "Press the new keys, then Return" : "Click, then press the new keys")
              : "These keys are fixed")
    }

    private func capColor(isRecording: Bool) -> Color {
        if isRecording { return pending == nil ? Color.secondary : Color.accentColor }
        return controller.isEnabled ? Color.primary : Color.secondary
    }

    private var recordingHint: String {
        if let message { return message }
        if pending != nil { return "Press Return to keep it, or type different keys. Esc cancels." }
        return "Press the new keys, then Return. Esc cancels."
    }

    private func note(_ text: String, isProblem: Bool) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isProblem ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions

    private func restoreDefaults() {
        stopRecording()
        controller.resetShortcuts()
    }

    // MARK: Recording

    private func startRecording(_ action: ShortcutAction) {
        stopRecording()
        recording = action
        pending = nil
        message = nil
        controller.setRecording(true)

        // A local monitor sees the keys typed in this app only, and can swallow them, so nothing beeps.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, for: action)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        recording = nil
        pending = nil
        message = nil
        controller.setRecording(false)
    }

    private func handle(_ event: NSEvent, for action: ShortcutAction) {
        let modifiers = Self.carbonModifiers(event.modifierFlags)
        let code = event.keyCode

        // Esc on its own cancels. (With a modifier it is a normal combination.)
        if modifiers == 0, code == 53 {
            stopRecording()
            return
        }

        // Return / Enter on its own keeps what was typed.
        if modifiers == 0, code == 36 || code == 76 {
            guard let pending else {
                message = "Type the new keys first, then press Return."
                return
            }
            if let refusal = controller.setShortcut(pending, for: action) {
                self.pending = nil
                message = refusal
            } else {
                stopRecording()
            }
            return
        }

        // Anything else is the new combination. It is checked when Return is pressed, but a combination that can
        // never be used is said so straight away.
        let typed = action.normalized(KeyShortcut(keyCode: UInt32(code), modifiers: modifiers))
        pending = typed
        message = typed.isAllowed ? nil : "Use at least one of ⌘, ⌥ or ⌃ with the key."
    }

    /// The modifier keys of an event, as the flag values global shortcuts use.
    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        let flags = flags.intersection(.deviceIndependentFlagsMask)
        var result: UInt32 = 0
        if flags.contains(.command) { result |= KeyShortcut.command }
        if flags.contains(.shift) { result |= KeyShortcut.shift }
        if flags.contains(.option) { result |= KeyShortcut.option }
        if flags.contains(.control) { result |= KeyShortcut.control }
        return result
    }
}
