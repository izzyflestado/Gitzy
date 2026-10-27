import SwiftUI

/// Milestone 3 placeholder. The real Contributions and Projects tabs arrive in Milestone 5.
/// The widget toggle is a test control that is removed in Milestone 6.
struct PopoverRootView: View {
    let widget: BranchWidgetController
    let projects: ProjectStore
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Gitzy").font(.headline)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .controlSize(.small)
            }

            Toggle("Show branch widget (test)", isOn: Binding(
                get: { widget.isVisible },
                set: { widget.setVisible($0) }
            ))
            .toggleStyle(.checkbox)

            Text(widget.elevationSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(height: 30, alignment: .topLeading)

            Divider()

            ProjectsTestView(store: projects, settings: settings)
        }
        .padding(16)
        .frame(width: 360, height: 440, alignment: .topLeading)
        .transaction { $0.animation = nil }
    }
}
