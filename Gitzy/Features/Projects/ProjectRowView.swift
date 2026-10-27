import SwiftUI

/// One project: name, branch, and the Finder / Terminal / remove buttons. Fixed height so lists never shift.
struct ProjectRowView: View {
    let row: ProjectRow
    let onReveal: () -> Void
    let onTerminal: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.project.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(row.project.path)

            Spacer(minLength: 8)

            Button(action: onReveal) { Image(systemName: "folder") }
                .help("Open in Finder")
                .disabled(row.status.isMissing)
            Button(action: onTerminal) { Image(systemName: "terminal") }
                .help("Open in Terminal")
                .disabled(row.status.isMissing)
            Button(action: onRemove) { Image(systemName: "minus.circle") }
                .help("Remove from Gitzy (files are not deleted)")
        }
        .buttonStyle(.borderless)
        .frame(height: 40)
    }

    private var subtitle: String {
        row.status.isMissing ? "Folder not found" : row.status.head.label
    }
}
