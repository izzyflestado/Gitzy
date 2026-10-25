import SwiftUI

/// Milestone 2 placeholder. The real Contributions and Projects tabs arrive in Milestone 5.
/// The controls below exist only to test the branch widget; they are removed in Milestone 6.
struct PopoverRootView: View {
    let widget: BranchWidgetController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Gitzy")
                .font(.headline)

            Text("Milestone 2 test controls")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle("Show branch widget", isOn: Binding(
                get: { widget.isVisible },
                set: { widget.setVisible($0) }
            ))
            .toggleStyle(.checkbox)

            Picker("Widget style", selection: Binding(
                get: { widget.backdrop },
                set: { widget.setBackdrop($0) }
            )) {
                ForEach(WidgetBackdrop.allCases) { style in
                    Text(style.label).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(widget.elevationSummary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("To test: show the widget, then open a fullscreen app. It should sit under the notch, above the app, and never take focus.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Quit Gitzy") { NSApp.terminate(nil) }
        }
        .padding(16)
        .frame(width: 360, height: 440, alignment: .topLeading)
        .transaction { $0.animation = nil }
    }
}
