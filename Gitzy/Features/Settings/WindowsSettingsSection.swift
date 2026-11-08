import SwiftUI

/// What "Open in Finder" and "Open in Terminal" do when a window of that app is already open.
/// It applies to the buttons in the project list and to the keyboard shortcuts.
struct WindowsSettingsSection: View {
    let settings: AppSettings

    @AppStorage(WindowMode.finderKey) private var finderMode: WindowMode = .newWindow
    @AppStorage(WindowMode.terminalKey) private var terminalMode: WindowMode = .newWindow

    var body: some View {
        Section("Finder and Terminal") {
            Picker("Open in Finder", selection: $finderMode) {
                ForEach(WindowMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Picker("Open in Terminal", selection: $terminalMode) {
                ForEach(WindowMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .disabled(!terminalCanShowExisting)
        }
    }

    /// Only Apple's Terminal can be asked which windows it has.
    private var terminalCanShowExisting: Bool {
        guard let app = settings.terminalAppURL else { return false }
        return TerminalWindows.isAppleTerminal(app)
    }
}
