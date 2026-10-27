import Foundation
import Observation

/// Everything about the GitHub connection, shared by every view: whether we are connected,
/// the last successful contribution data, and the one refresh timer.
///
/// The token itself is never held here. It is read from the Keychain for each request and handed
/// straight to GitHubService, so it is never stored in a property, in UserDefaults, or in a log.
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
    private(set) var tokenStorage: KeychainService.Storage?
    /// True when a scheduled refresh was skipped because Low Power Mode is on.
    private(set) var pausedForLowPower = false
    /// Result of the Milestone 4 earlier-years test.
    private(set) var yearCheckText: String?
    private(set) var isCheckingYears = false

    var isConnected: Bool { login != nil }

    private let settings: AppSettings
    private let service = GitHubService()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    /// The Keychain clean-up of the last Disconnect. A new token is not saved until it has finished.
    @ObservationIgnored private var disconnectTask: Task<Void, Never>?
    /// Do not contact GitHub before this moment (rate limit).
    @ObservationIgnored private var blockedUntil: Date?
    /// Bumped on connect and disconnect so a refresh that was already running cannot write into the new state.
    @ObservationIgnored private var generation = 0

    private static let loginKey = "githubLogin"
    private static let fallbackBlock: TimeInterval = 15 * 60

    init(settings: AppSettings) {
        self.settings = settings
        login = UserDefaults.standard.string(forKey: Self.loginKey)
        guard login != nil else { return }
        Task {
            tokenStorage = await Task.detached { KeychainService.currentStorage() }.value
        }
        refresh()
        restartTimer()
    }

    // MARK: Connecting

    /// Checks the token with GitHub, saves it in the Keychain, and starts loading contributions.
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
        let storage: KeychainService.Storage
        do {
            storage = try await Task.detached { try KeychainService.save(token: token) }.value
        } catch let failure as KeychainService.Failure {
            setTokenMessage("The token is valid, but the Keychain would not save it: \(failure.message)", isError: true)
            return false
        } catch {
            setTokenMessage("The token is valid, but the Keychain would not save it.", isError: true)
            return false
        }

        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        isLoading = false
        isCheckingYears = false
        yearCheckText = nil
        if info.login != login { snapshot = nil }
        blockedUntil = nil
        refreshError = nil
        pausedForLowPower = false
        login = info.login
        tokenStorage = storage
        UserDefaults.standard.set(info.login, forKey: Self.loginKey)
        await service.clearCache()

        setTokenMessage("Connected as @\(info.login). The token is stored in the \(storage.label).", isError: false)
        tokenWarning = ScopeReport(scopes: info.scopes).warning

        refresh()
        restartTimer()
        return true
    }

    /// Removes the token from the Keychain and forgets everything that came from GitHub.
    func disconnect() {
        resetConnection()
        setTokenMessage("Disconnecting…", isError: false)
        disconnectTask = Task {
            await Task.detached { KeychainService.delete() }.value
            let leftover = await Task.detached { KeychainService.currentStorage() }.value
            if leftover == nil {
                setTokenMessage("Disconnected. The token was removed from the Keychain. To make it useless everywhere, also delete it at github.com/settings/tokens.", isError: false)
            } else {
                setTokenMessage("Disconnected, but the Keychain would not remove the token. Delete the item named \"Gitzy GitHub token\" in Keychain Access.", isError: true)
            }
            await service.clearCache()
        }
    }

    /// Milestone 4 test: fetches the totals of the four years before this one in a single request,
    /// the same request used to extend long streaks, so they can be compared with the GitHub profile.
    func checkEarlierYears() {
        guard isConnected, !isCheckingYears else { return }
        guard let newest = snapshot?.weeks.last?.last?.date, let thisYear = Int(newest.prefix(4)) else {
            yearCheckText = "Load your contributions first."
            return
        }
        if let until = blockedUntil, until > Date() {
            yearCheckText = GitHubError.rateLimited(retryAfter: until).message
            return
        }
        isCheckingYears = true
        yearCheckText = "Checking…"
        let mine = generation
        Task {
            defer { if mine == generation { isCheckingYears = false } }
            let token = await Task.detached { KeychainService.load() }.value
            guard mine == generation, let token else { return }
            let years = [thisYear - 1, thisYear - 2, thisYear - 3, thisYear - 4]
            do {
                let totals = try await service.yearTotals(years, token: token)
                guard mine == generation else { return }
                yearCheckText = years.map { "\($0): \(totals[$0] ?? 0)" }.joined(separator: "   ")
            } catch is CancellationError {
                return
            } catch let error as GitHubError {
                guard mine == generation else { return }
                yearCheckText = error.message
            } catch {
                guard mine == generation else { return }
                yearCheckText = GitHubError.network.message
            }
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

        let token = await Task.detached { KeychainService.load() }.value
        guard mine == generation else { return }
        guard let token else {
            lostToken()
            return
        }

        do {
            let result = try await service.loadContributions(token: token)
            guard mine == generation else { return }
            snapshot = result
            refreshError = nil
            blockedUntil = nil
            pausedForLowPower = false
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
            // Manual refresh still works, and Replace token fixes it.
            refreshError = error.message
            timer?.invalidate()
            timer = nil
        case .noToken:
            lostToken()
        default:
            refreshError = error.message
        }
    }

    /// The Keychain no longer has the token (deleted in Keychain Access, for example).
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
        snapshot = nil
        refreshError = nil
        blockedUntil = nil
        pausedForLowPower = false
        yearCheckText = nil
        isCheckingYears = false
        tokenStorage = nil
        tokenWarning = nil
        UserDefaults.standard.removeObject(forKey: Self.loginKey)
    }

    private func setTokenMessage(_ text: String, isError: Bool) {
        tokenMessage = text
        tokenMessageIsError = isError
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
