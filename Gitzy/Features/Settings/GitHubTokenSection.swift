import AppKit
import SwiftUI

/// Connect, replace and disconnect the GitHub token. Lives in the Settings window.
///
/// The token is held only while it is being typed (in `pastedToken`) and is cleared the moment Connect is pressed.
/// The Settings window is thrown away when it closes, so nothing typed can stay behind in it.
struct GitHubTokenSection: View {
    let store: ContributionStore

    @State private var pastedToken = ""
    @State private var isReplacing = false

    private static let createTokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=read:user&description=Gitzy")

    /// Written as ~/Library/..., so it reads the same on every Mac.
    private static let tokenLocation = (TokenFile.standard.fileURL.path as NSString).abbreviatingWithTildeInPath

    private static let help = "Use a classic token with only the read:user permission. It is only ever sent to api.github.com. Private contributions count only if \"Include private contributions on my profile\" is switched on in your GitHub profile settings."

    private let avatarSize: CGFloat = 36

    private var showsField: Bool { !store.isConnected || isReplacing }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsField { tokenField } else { connectedRow }

            if let message = visibleMessage {
                note(message, isProblem: store.tokenMessageIsError)
            }
            if let warning = store.tokenWarning {
                note(warning, isProblem: true)
            }
            if showsField {
                note(Self.help, isProblem: false)
            }
            note("Saved on this Mac in a private file: \(Self.tokenLocation). Other user accounts on this Mac cannot read it.", isProblem: false)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    // MARK: Pieces

    private var connectedRow: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected as @\(store.login ?? "")")
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("Token saved on this Mac")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Button("Replace token") {
                    store.clearTokenMessages()
                    isReplacing = true
                }
                Button("Disconnect") {
                    pastedToken = ""
                    isReplacing = false
                    store.disconnect()
                }
            }
            .controlSize(.small)
        }
    }

    private var avatar: some View {
        Group {
            if let image = store.avatar {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: avatarSize, height: avatarSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var tokenField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("Paste your token here", text: $pastedToken)
                .textFieldStyle(.roundedBorder)
                .onSubmit(connect)
                .disabled(store.isCheckingToken)
            HStack {
                Button("Connect", action: connect)
                    .disabled(pastedToken.isEmpty || store.isCheckingToken)
                if isReplacing {
                    Button("Cancel") {
                        pastedToken = ""
                        isReplacing = false
                        store.clearTokenMessages()
                    }
                }
                Spacer()
                if let url = Self.createTokenURL {
                    Link("Create token", destination: url)
                }
            }
            .controlSize(.small)
        }
    }

    /// Once connected, the row above already says so, so only a problem is worth showing.
    /// While there is no token (or a new one is being checked) every message is shown.
    private var visibleMessage: String? {
        guard let message = store.tokenMessage else { return nil }
        return showsField || store.tokenMessageIsError ? message : nil
    }

    private func note(_ text: String, isProblem: Bool) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isProblem ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Actions

    private func connect() {
        let value = pastedToken
        guard !value.isEmpty else { return }
        pastedToken = ""   // the field is empty from here on, whatever happens next
        Task {
            if await store.connect(token: value) {
                isReplacing = false
            }
        }
    }
}
