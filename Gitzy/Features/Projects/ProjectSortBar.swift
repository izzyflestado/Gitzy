import AppKit
import SwiftUI

/// The sort button: an icon beside refresh. Clicking it opens a normal macOS menu, centred under the icon.
///
/// SwiftUI's own Menu lets macOS decide where the menu opens. Opening the menu through AppKit instead
/// means Gitzy chooses the spot, so it can sit centred under the button.
struct ProjectSortBar: View {
    let store: ProjectStore

    /// Remembers an invisible view that has exactly the button's size, which the menu is positioned from.
    @State private var anchor = MenuAnchor()

    var body: some View {
        Button(action: openMenu) {
            Image(systemName: "arrow.up.arrow.down")
                .frame(width: 16)
        }
        .background(AnchorView(anchor: anchor))
        .help("Sort: \(store.sort.shortLabel)")
        .accessibilityLabel("Sort projects")
    }

    private func openMenu() {
        guard let view = anchor.view else { return }

        // The menu items point at this handler, and items only hold it weakly, so it stays in this function
        // for as long as the menu is open.
        let handler = SortMenuHandler { store.setSort($0) }

        let menu = NSMenu()
        menu.autoenablesItems = false
        for option in ProjectSort.allCases {
            let item = NSMenuItem(title: option.menuLabel, action: #selector(SortMenuHandler.choose(_:)), keyEquivalent: "")
            item.target = handler
            item.representedObject = option.rawValue
            item.state = option == store.sort ? .on : .off
            menu.addItem(item)
        }

        // Centred under the button, with a small gap. The y direction depends on whether the view is flipped.
        let x = view.bounds.midX - menu.size.width / 2
        let y = view.isFlipped ? view.bounds.maxY + 4 : view.bounds.minY - 4
        menu.popUp(positioning: nil, at: NSPoint(x: x, y: y), in: view)
    }
}

// MARK: Helpers

/// Holds the invisible view the menu is placed from.
private final class MenuAnchor {
    weak var view: NSView?
}

/// A view that takes the button's place in the layout but never takes a click.
private final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct AnchorView: NSViewRepresentable {
    let anchor: MenuAnchor

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughView()
        anchor.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        anchor.view = nsView
    }
}

/// Receives the menu choice and passes it on.
private final class SortMenuHandler: NSObject {
    private let onPick: (ProjectSort) -> Void

    init(onPick: @escaping (ProjectSort) -> Void) {
        self.onPick = onPick
    }

    @objc func choose(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let sort = ProjectSort(rawValue: raw) else { return }
        onPick(sort)
    }
}
