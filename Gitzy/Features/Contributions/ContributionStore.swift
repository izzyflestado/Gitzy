import AppKit
import Foundation
import Observation

/// Everything about the GitHub connection, shared by every view: whether we are connected,
/// the last successful contribution data, and the one refresh timer.
///
/// The token itself is never held here. It is read from its private file (see TokenFile) for each request and
/// handed straight to GitHubService, so it is never stored in a property, in UserDefaults, or in a log.
@Observable
final class ContributionStore {
    // What the views show.
    private(set) var login: String?
    private(set) var snapshot: ContributionSnapshot?
    private(set) var isLoading = false
    private(set) var isCheckingToken = false
    /// Why the last refresh failed. The last good `snapshot` stays on screen next to it.
    private(set) var refreshError: String?
    private(set) var tokenMessage: String?
    private(set) var tokenMessageIsError = false
    private(set) var tokenWarning: String?
    /// True when a scheduled refresh was skipped because Low Power Mode is on.
    private(set) var pausedForLowPower = false
    /// True when GitHub has refused the saved token (expired or revoked). The token controls reappear until it is replaced.
    private(set) var tokenRejected = false
    /// The profile picture, kept in memory only. Nil until it has downloaded, and the tab shows a plain placeholder.
    private(set) var avatar: NSImage?

    var isConnected: Bool { login != nil }

    /// "Recent activity" under the graph. It loads separately, so the graph never waits for it.
    let activity = RecentActivityStore()

    private let settings: AppSettings
    private let service = GitHubService()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// The token-file clean-up of the last Disconnect. A new token is not saved until it has finished.
    @ObservationIgnored private var disconnectTask: Task<Void, Never>?
    /// Do not contact GitHub before this moment (rate limit).
    @ObservationIgnored private var blockedUntil: Date?
    /// The picture address `avatar` came from, so the picture is only downloaded again when it changes.
    @ObservationIgnored private var avatarSource: URL?
    @ObservationIgnored private var avatarTask: Task<Void, Never>?
    /// Bumped on connect and disconnect so a refresh that was already running cannot write into the new state.
    @ObservationIgnored private var generation = 0

    private static let loginKey = "githubLogin"
    private static let fallbackBlock: TimeInterval = 15 * 60

    init(settings: AppSettings) {
        self.settings = settings
        login = UserDefaults.standard.string(forKey: Self.loginKey)
        guard login != nil else { return }
        refresh()
        restartTimer()
    }

    // MARK: Connecting

    /// Checks the token with GitHub, saves it in its private file, and starts loading contributions.
    /// Returns true when the token was accepted and saved.
    func connect(token rawToken: String) async -> Bool {
        guard !isCheckingToken else { return false }
        guard let token = TokenFormat.cleaned(rawToken) else {
            setTokenMessage("That does not look like a GitHub token. Paste the whole token, with nothing else.", isError: true)
            return false
        }

        isCheckingToken = true
        tokenWarning = nil
        setTokenMessage("Checking the token with GitHub…", isError: false)
        defer { isCheckingToken = false }

        let info: TokenInfo
        do {
            info = try await service.validate(token: token)
        } catch let error as GitHubError {
            if case .invalidToken = error {
                setTokenMessage("GitHub rejected that token. Check that you copied all of it and that it has not expired.", isError: true)
            } else {
                setTokenMessage(error.message, isError: true)
            }
            return false
        } catch {
            setTokenMessage(GitHubError.network.message, isError: true)
            return false
        }

        await disconnectTask?.value   // never let an old Disconnect delete the new token
        do {
            try await Task.detached { try TokenFile.standard.save(token: token) }.value
        } catch let failure as TokenFile.Failure {
            setTokenMessage("The token is valid, but it could not be saved. \(failure.message)", isError: true)
            return false
        } catch {
            setTokenMessage("The token is valid, but it could not be saved.", isError: true)
            return false
        }

        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        isLoading = false
        if info.login != login {
            snapshot = nil
            clearAvatar()
        }
        blockedUntil = nil
        refreshError = nil
        pausedForLowPower = false
        tokenRejected = false
        login = info.login
        UserDefaults.standard.set(info.login, forKey: Self.loginKey)
        await service.clearCache()

        setTokenMessage("Connected as @\(info.login). The token is saved on this Mac.", isError: false)
        tokenWarning = ScopeReport(scopes: info.scopes).warning

        refresh()
        restartTimer()
        return true
    }

    /// Deletes the saved token and forgets everything that came from GitHub.
    func disconnect() {
        resetConnection()
        setTokenMessage("Disconnecting…", isError: false)
        disconnectTask = Task {
            let removed = await Task.detached { TokenFile.standard.delete() }.value
            if removed {
                setTokenMessage("Disconnected. The saved token was deleted. To make it useless everywhere, also delete it at github.com/settings/tokens.", isError: false)
            } else {
                setTokenMessage("Disconnected, but Gitzy could not delete its token file. Delete the file named github-token in the Gitzy folder inside ~/Library/Application Support.", isError: true)
            }
            await service.clearCache()
        }
    }

    func clearTokenMessages() {
        tokenMessage = nil
        tokenMessageIsError = false
        tokenWarning = nil
    }

    // MARK: Refreshing

    /// Loads fresh data. Does nothing while another refresh is running, and waits out a rate limit.
    func refresh() {
        guard isConnected, !isLoading else { return }
        if let until = blockedUntil, until > Date() {
            refreshError = GitHubError.rateLimited(retryAfter: until).message
            return
        }
        isLoading = true
        refreshTask = Task { await performRefresh() }
    }

    func setRefreshInterval(_ minutes: Int) {
        settings.setRefreshInterval(minutes)
        restartTimer()
    }

    // MARK: Private

    private func performRefresh() async {
        let mine = generation
        defer {
            if mine == generation {
                isLoading = false
                refreshTask = nil
            }
        }

        let stored = await Task.detached { TokenFile.standard.load() }.value
        guard mine == generation else { return }
        let token: String
        switch stored {
        case .found(let value):
            token = value
        case .missing:
            lostToken()
            return
        case .unreadable:
            // The file is there but could not be read this time. That is not a reason to forget the connection.
            refreshError = "Gitzy could not read its saved token. Try Refresh again."
            return
        }

        do {
            let result = try await service.loadContributions(token: token)
            guard mine == generation else { return }
            snapshot = result
            refreshError = nil
            blockedUntil = nil
            pausedForLowPower = false
            tokenRejected = false
            loadAvatarIfNeeded(for: result)
            activity.refresh(login: result.login)
        } catch is CancellationError {
            return
        } catch let error as GitHubError {
            guard mine == generation else { return }
            handle(error)
        } catch {
            guard mine == generation else { return }
            refreshError = GitHubError.network.message
        }
    }

    private func handle(_ error: GitHubError) {
        switch error {
        case .rateLimited(let retryAfter):
            let until = retryAfter ?? Date().addingTimeInterval(Self.fallbackBlock)
            blockedUntil = until
            refreshError = GitHubError.rateLimited(retryAfter: until).message
        case .invalidToken:
            // A rejected token will not start working by itself, so stop the schedule.
            // Manual refresh still works, and replacing the token fixes it.
            refreshError = error.message
            tokenRejected = true
            timer?.invalidate()
            timer = nil
        case .noToken:
            lostToken()
        default:
            refreshError = error.message
        }
    }

    /// There is no saved token any more (the token file was deleted, for example).
    private func lostToken() {
        resetConnection()
        setTokenMessage(GitHubError.noToken.message, isError: true)
    }

    private func resetConnection() {
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        timer?.invalidate()
        timer = nil
        isLoading = false
        login = nil
        activity.reset()
        snapshot = nil
        refreshError = nil
        blockedUntil = nil
        pausedForLowPower = false
        tokenRejected = false
        tokenWarning = nil
        clearAvatar()
        UserDefaults.standard.removeObject(forKey: Self.loginKey)
    }

    private func setTokenMessage(_ text: String, isError: Bool) {
        tokenMessage = text
        tokenMessageIsError = isError
    }

    // MARK: Profile picture

    /// Downloads the picture the first time, and again only when GitHub's address for it changes.
    /// A failed download changes nothing: the placeholder (or the previous picture) stays, and the next refresh tries again.
    private func loadAvatarIfNeeded(for snapshot: ContributionSnapshot) {
        guard let url = snapshot.avatarURL else { return }
        if url == avatarSource, avatar != nil { return }
        avatarTask?.cancel()
        let mine = generation
        avatarTask = Task {
            do {
                let data = try await service.loadAvatar(from: url)
                guard mine == generation, !Task.isCancelled, let image = NSImage(data: data) else { return }
                avatar = image
                avatarSource = url
            } catch {
                // Nothing to report: the picture is a nicety, and the token was never involved.
            }
        }
    }

    private func clearAvatar() {
        avatarTask?.cancel()
        avatarTask = nil
        avatar = nil
        avatarSource = nil
    }

    // MARK: The one timer

    /// The only timer in the app. It is generous about when it fires (20% tolerance) so macOS
    /// can batch it with other wake-ups, and it is skipped entirely in Low Power Mode.
    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        let minutes = settings.refreshIntervalMinutes
        guard minutes > 0, isConnected else { return }

        let interval = TimeInterval(minutes * 60)
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scheduledRefresh() }
        }
        newTimer.tolerance = interval * 0.2
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func scheduledRefresh() {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            pausedForLowPower = true
            return
        }
        refresh()
    }
}
