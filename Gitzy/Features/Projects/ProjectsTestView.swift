import SwiftUI

/// The Projects tab: three action buttons on top, then the saved projects.
/// Still the interim design; the final polish arrives in Milestone 5 and reuses ProjectRowView.
struct ProjectsTestView: View {
    let store: ProjectStore

    /// Every press of Refresh adds one full turn, which is what makes the icon spin once.
    @State private var refreshTurns = 0

    var body: some View {
        VStack(spacing: 10) {
            actions
            list
        }
    }

    // MARK: Buttons

    /// Not covered by the "no animation" rule below on purpose: the spinning refresh icon is the one animation in the app.
    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                FilePickers.chooseFolder(message: "Choose a Git project folder") { store.addProject(at: $0) }
            } label: {
                Label("Add Project", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }

            // Same size and place while scanning, so nothing shifts: the button simply becomes Stop.
            Button(action: scanOrStop) {
                Label(store.isScanning ? "Stop Scan" : "Scan Folder",
                      systemImage: store.isScanning ? "xmark" : "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }

            Button(action: refresh) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(Double(refreshTurns) * 360))
                    .animation(.linear(duration: 1), value: refreshTurns)
                    .frame(width: 16)
            }
            .help("Refresh the branch of every project")
            .accessibilityLabel("Refresh")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(store.rows) { row in
                    ProjectRowView(
                        row: row,
                        onFinder: { store.openInFinder(row.project) },
                        onTerminal: { store.openInTerminal(row.project) },
                        onRemove: { store.remove(row.project) }
                    )
                    Divider()
                }
            }
            // The scroll bar floats over the right edge, so keep the buttons clear of it.
            .padding(.trailing, 14)
        }
        .frame(maxHeight: .infinity)
        .overlay {
            if store.rows.isEmpty { emptyState }
        }
        .overlay(alignment: .bottom) { problemLine }
        .transaction { $0.animation = nil }
    }

    private var emptyState: some View {
        Text("No projects yet.\nAdd one, or scan a folder.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    /// Only shown when something went wrong. Adding and removing projects say nothing.
    @ViewBuilder private var problemLine: some View {
        if let problem = store.problem {
            HStack(alignment: .top, spacing: 6) {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { store.clearProblem() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.borderless)
                .help("Dismiss")
                .accessibilityLabel("Dismiss message")
            }
            .padding(8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    // MARK: Actions

    private func scanOrStop() {
        if store.isScanning {
            store.cancelScan()
        } else {
            FilePickers.chooseFolder(message: "Choose a folder to scan for Git projects (3 levels deep)") { store.scan(folder: $0) }
        }
    }

    private func refresh() {
        store.clearProblem()
        refreshTurns += 1
        Task { await store.refresh() }
    }
}
