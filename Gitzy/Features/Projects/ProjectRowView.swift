import SwiftUI

/// One project: name, branch, and the Finder / Terminal / GitHub / remove buttons. Fixed height so lists never shift.
struct ProjectRowView: View {
    let row: ProjectRow
    let onFinder: () -> Void
    let onTerminal: () -> Void
    let onGitHub: () -> Void
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

            Button(action: onGitHub) { Image(systemName: "arrow.up.right.square") }   // moved here
                .help(githubHelp)
                .disabled(row.status.isMissing || row.status.githubURL == nil)
                .accessibilityLabel("Open repository on GitHub")
            Button(action: onFinder) { Image(systemName: "folder") }
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

    /// "Open octocat/hello on GitHub", or why the button is grayed out.
    private var githubHelp: String {
        guard let url = row.status.githubURL else { return "No GitHub remote found" }
        return "Open \(url.path.dropFirst()) on GitHub"
    }

    private var subtitle: String {
        if row.status.isMissing { return "Folder not found" }
        if let detail = row.detail { return "\(row.status.head.label) · \(detail)" }
        return row.status.head.label
    }
}
