import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Which code editor "Open in default IDE" uses.
///
/// Automatic (the default) lets the project decide: Xcode for Xcode projects and Swift packages, VS Code for
/// everything else. Choosing an app here makes every project open in that app instead.
struct IDESettingsSection: View {
    let settings: AppSettings

    var body: some View {
        Section("Default IDE") {
            LabeledContent("Open in default IDE") {
                HStack(spacing: 8) {
                    Text(shownName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Button("Choose…", action: choose)
                    Button("Automatic") { settings.setIDEApp(nil) }
                        .disabled(settings.ideAppPath == nil)
                }
                .controlSize(.small)
            }

            Text(explanation)
                .font(.system(size: 11))
                .foregroundStyle(chosenIsMissing ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: What is chosen

    /// The chosen app, when one is chosen and still installed.
    private var chosenURL: URL? {
        guard let path = settings.ideAppPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Something was chosen, but the app has since been moved or deleted.
    private var chosenIsMissing: Bool {
        settings.ideAppPath != nil && chosenURL == nil
    }

    private var shownName: String {
        chosenURL.map { $0.deletingPathExtension().lastPathComponent } ?? "Automatic"
    }

    private var explanation: String {
        if chosenIsMissing {
            return "The app you chose is no longer there, so Automatic is being used. Choose another one."
        }
        if let url = chosenURL {
            return "Every project opens in \(url.deletingPathExtension().lastPathComponent), whatever kind of project it is."
        }
        return "Automatic opens Xcode for Xcode projects and Swift packages, and VS Code for everything else (Xcode when VS Code is not installed)."
    }

    // MARK: Choosing

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose a code editor"
        panel.message = "Pick the app that \"Open in default IDE\" should use."
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        settings.setIDEApp(url)
    }
}
