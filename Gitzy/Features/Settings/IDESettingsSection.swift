import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Which code editor "Open in default IDE" uses, in two rows.
///
/// Row 1: Automatic, blue while it is in use. Automatic lets the project decide: Xcode for Xcode projects and Swift
/// packages, VS Code for everything else.
/// Row 2: a chosen app, shown with its icon and name; hovering it says Choose. Choosing an app makes every project open
/// in that app instead. If the chosen app has since been moved or deleted, Automatic is used and shows blue.
struct IDESettingsSection: View {
    let settings: AppSettings

    @State private var hoveringChoice = false

    var body: some View {
        Section("Default IDE") {
            LabeledContent("Open in default IDE") {
                Button("Automatic") { settings.setIDEApp(nil) }
                    .buttonStyle(.borderedProminent)
                    .tint(chosenURL == nil ? Color.accentColor : Color.gray)
                    .controlSize(.small)
            }

            LabeledContent("Specific app") {
                Button(action: choose) {
                    HStack(spacing: 6) {
                        if let url = chosenURL, !hoveringChoice {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(url.deletingPathExtension().lastPathComponent)
                                .lineLimit(1)
                        } else {
                            Text("Choose…")
                        }
                    }
                    .frame(minWidth: 110)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .onHover { hoveringChoice = $0 }
            }
        }
    }

    // MARK: What is chosen

    /// The chosen app, when one is chosen and still installed.
    private var chosenURL: URL? {
        guard let path = settings.ideAppPath, FileManager.default.fileExists(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
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
