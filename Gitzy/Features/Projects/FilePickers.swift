import AppKit
import UniformTypeIdentifiers

/// The native open panels used by the Projects feature.
enum FilePickers {
    static func chooseFolder(message: String, onPick: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        present(panel, onPick: onPick)
    }

    static func chooseApplication(onPick: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.message = "Choose your terminal app"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        present(panel, onPick: onPick)
    }

    private static func present(_ panel: NSOpenPanel, onPick: @escaping (URL) -> Void) {
        NSApp.activate()   // Gitzy has no Dock icon, so bring the panel to the front explicitly
        panel.begin { response in
            if response == .OK, let url = panel.url { onPick(url) }
        }
    }
}
