import SwiftUI

/// The GitHub account part of Settings: the account and token.
/// The refresh settings are in ContributionsIDESection, next to the default IDE.
struct GitHubSettingsSection: View {
    let store: ContributionStore
    let settings: AppSettings

    var body: some View {
        Section("GitHub account") {
            GitHubTokenSection(store: store)
        }
    }
}
