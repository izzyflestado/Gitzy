import AppKit
import SwiftUI

/// The keys that switch tabs while the Gitzy menu is open. They are plain keys, used only inside the menu.
///
/// To change one: click its key, then press the new key. Esc cancels. A key another tab already uses is refused.
struct TabKeysSettingsSection: View {
    let settings: AppSettings
    private let tabNames = ["Projects tab", "Widget tab", "GitHub tab"]
    /// Index of the tab being recorded, if any.
    @State private var recording: Int?
    @State private var message: String?
    @State private var monitor: Any?

    var body: some View {
        Section {
            ForEach(tabNames.indices, id: \.self) { index in
                LabeledContent(tabNames[index]) {
                    keyCap(index)
                }
                if recording == index {
                    Text(message ?? "Press the new key. Esc cancels.")
                        .font(.system(size: 11))
                        .foregroundStyle(message == nil ? Color.secondary : Color.orange)
                }
            }
        } header: {
            HStack {
                Text("Menu tab keys")
                Spacer()
                Button("Restore Defaults") {
                    stopRecording()
                    settings.resetTabKeys()
                }
                .controlSize(.small)
                .disabled(settings.tabKeys == AppSettings.defaultTabKeys)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in stopRecording() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { _ in stopRecording() }
        .onDisappear { stopRecording() }
    }

    private func keyCap(_ index: Int) -> some View {
        let isRecording = recording == index
        return Button {
            isRecording ? stopRecording() : startRecording(index)
        } label: {
            Text(isRecording ? "Type key…" : settings.tabKeys[index].uppercased())
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(isRecording ? Color.secondary : Color.primary)
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
        .help(isRecording ? "Press the new key" : "Click, then press the new key")
    }

    private func startRecording(_ index: Int) {
        stopRecording()
        recording = index
        message = nil
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event, for: index)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        recording = nil
        message = nil
    }

    private func handle(_ event: NSEvent, for index: Int) {
        let flags = event.modifierFlags.intersection([.command, .option, .control])
        if flags.isEmpty, event.keyCode == 53 {   // Esc
            stopRecording()
            return
        }
        guard flags.isEmpty,
              let key = event.charactersIgnoringModifiers?.lowercased(),
              key.count == 1,
              let scalar = key.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              !CharacterSet.whitespaces.contains(scalar),
              scalar.value < 0xF700 || scalar.value > 0xF8FF   // arrows, F-keys and similar
        else {
            message = "Use a letter, number or symbol key, without ⌘, ⌥ or ⌃."
            return
        }
        if let refusal = settings.setTabKey(key, at: index) {
            message = refusal
        } else {
            stopRecording()
        }
    }
}
