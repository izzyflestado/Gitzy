import SwiftUI

/// Milestone 3 test UI inside the popover. The real Projects tab arrives in Milestone 5
/// and reuses ProjectRowView.
struct ProjectsTestView: View {
    let store: ProjectStore
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button("Add…") {
                    FilePickers.chooseFolder(message: "Choose a Git project folder") { store.addProject(at: $0) }
                }
                Button("Scan…") {
                    FilePickers.chooseFolder(message: "Choose a folder to scan for Git projects (3 levels deep)") { store.scan(folder: $0) }
                }
                if store.isScanning {
                    Button("Stop") { store.cancelScan() }
                }
                Spacer()
                Button("Refresh") { Task { await store.refresh() } }
            }
            .controlSize(.small)

            Text(store.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(height: 30, alignment: .topLeading)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(store.rows) { row in
                        ProjectRowView(
                            row: row,
                            onReveal: { store.reveal(row.project) },
                            onTerminal: { store.openInTerminal(row.project) },
                            onRemove: { store.remove(row.project) }
                        )
                        Divider()
                    }
                }
            }
            .frame(maxHeight: .infinity)

            HStack {
                Text("Terminal: \(settings.terminalName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Choose…") { FilePickers.chooseApplication { settings.setTerminalApp($0) } }
                Button("Built-in") { settings.setTerminalApp(nil) }
            }
            .controlSize(.small)
        }
    }
}
