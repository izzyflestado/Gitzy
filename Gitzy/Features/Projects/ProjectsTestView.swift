import SwiftUI

/// The Projects tab: three action buttons on top, then the saved projects.
/// Rows can be dragged up and down to sort them; the order is saved.
/// Still the interim design; the final polish arrives in Milestone 5 and reuses ProjectRowView.
struct ProjectsTestView: View {
    let store: ProjectStore

    /// The room to the left of the list that the row numbers hang in: the popover's own 16 pt side padding,
    /// which the list is widened into. Rows and underlines start exactly where they always did.
    private static let numberGutter: CGFloat = 16

    /// How far the (bigger) number reaches into the row, past the margin. The row's content starts this much
    /// further right to make room; the underline does not move.
    private static let numberOverhang: CGFloat = 8

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
            
            ProjectSortBar(store: store)
            
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

    /// A List rather than a ScrollView, because only a List lets rows be dragged into a new order (.onMove).
    /// The look stays as before: no built-in insets, separators or background (each row draws its own Divider).
    private var list: some View {
        List {
            ForEach(Array(store.rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .top, spacing: 0) {
                    // The number hangs in the popover's side margin, to the left of the row and its underline.
                    Text("\(index + 1)")
                        .font(.system(size: 16, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(width: Self.numberGutter + Self.numberOverhang, height: 40)   // 40 = the height of a row
                        .padding(.trailing, -Self.numberOverhang)   // reaches into the row; the row's place and the underline do not change
                    VStack(spacing: 0) {
                        ProjectRowView(
                            row: row,
                            onFinder: { store.openInFinder(row.project) },
                            onTerminal: { store.openInTerminal(row.project) },
                            onGitHub: { store.openOnGitHub(row) },
                            onIDE: { store.openInIDE(row.project) },
                            onRemove: { store.remove(row.project) }
                        )
                        .padding(.leading, Self.numberOverhang)
                        Divider()
                    }
                }
                // The scroll bar floats over the right edge, so keep the buttons clear of it.
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 4))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
            .onMove { store.move(fromOffsets: $0, toOffset: $1) }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        // Widened into the popover's side margin, so the row numbers can hang there, left of the underlines.
        .padding(.leading, -Self.numberGutter)
        .frame(maxHeight: .infinity)
        .overlay {
            if store.rows.isEmpty { emptyState.padding(.leading, Self.numberGutter) }
        }
        .overlay(alignment: .bottom) { problemLine.padding(.leading, Self.numberGutter) }
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
