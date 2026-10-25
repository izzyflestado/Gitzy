import SwiftUI

@main
struct GitzyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Gitzy has no main window. SwiftUI needs at least one scene, so this is an empty placeholder.
    var body: some Scene {
        Settings { EmptyView() }
    }
}
