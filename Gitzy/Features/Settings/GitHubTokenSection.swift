import SwiftUI

/// Connect, replace and disconnect the GitHub token. Used inside the popover for now;
/// it moves into the Settings window in Milestone 5.
struct GitHubTokenSection: View {
    let store: ContributionStore

    /// Held only while the person is typing. It is cleared the moment they press Connect.
    @State private var pastedToken = ""
    @State private var isReplacing = false

    private static let createTokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=read:user&description=Gitzy")

    private var showsField: Bool { !store.isConnected || isReplacing }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsField { tokenField } else { connectedRow }

            if let message = store.tokenMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(store.tokenMessageIsError ? Color.orange : Color.secondary)
                    .lineLimit(3)
            }
            if let warning = store.tokenWarning {
                Text(warning)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }
            if showsField { help }
        }
    }

    // MARK: Pieces

    private var connectedRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Connected as @\(store.login ?? "")")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(storageText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
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

    private var tokenField: some View {
        VStack(alignment: .leading, spacing: 6) {
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

    private var help: some View {
        Text("Use a classic token with only the read:user permission. It is stored in your Keychain and is only ever sent to api.github.com. Private contributions count only if \"Include private contributions on my profile\" is switched on in your GitHub profile settings.")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var storageText: String {
        guard let storage = store.tokenStorage else { return "Token stored in the Keychain" }
        return "Token stored in the \(storage.label)"
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
