import AppKit

/// Lets the apps in view decide whether the branch widget is showing ("Widget by app" in Settings).
///
/// Off by default. While it is on and at least one app has a rule, Gitzy reads the list of windows that are on screen
/// twice a second, works out which apps are really visible (see WindowCoverage), and applies the rules (see
/// VisibilityRules). With the switch off, or no apps added, there is no timer and no observer, and nothing is read.
///
/// The widget changes only after two reads in a row agree. Switching Space or going fullscreen shows half-finished
/// states for a moment, and this keeps the widget from blinking through them. Changing a setting applies at once.
///
/// It can only HIDE a widget the person has switched on. `allowsWidget` is what BranchWidgetController asks.
/// No permission is needed, and no window titles or contents are read.
@Observable
final class AppVisibilityMonitor {
    private static let enabledKey = "appVisibilityEnabled"
    private static let thresholdKey = "appVisibilityThreshold"
    private static let priorityKey = "appVisibilityPriority"
    private static let rulesKey = "appVisibilityRules"

    /// How much of an app's window must be uncovered for the app to count as visible.
    static let thresholdRange: ClosedRange<Double> = 0.10...1.0
    static let defaultThreshold = 0.33
    /// The uncovered part must also be at least about 200 by 200 points, so a tiny popup does not count.
    static let minimumVisibleArea = 40_000.0
    private static let pollInterval: TimeInterval = 0.5

    // MARK: Saved settings

    private(set) var isEnabled = false
    private(set) var threshold = AppVisibilityMonitor.defaultThreshold
    private(set) var priority = RulePriority.standard
    /// Bundle identifier to rule.
    private(set) var rules: [String: AppRule] = [:]

    // MARK: Outcome

    /// False only while the rules say the widget should be out of sight.
    private(set) var allowsWidget = true
    /// What was seen and why the widget is shown or hidden. Empty while the feature is not running.
    private(set) var statusLine = ""

    /// Running means the timer and the observers exist.
    var isActive: Bool { isEnabled && !rules.isEmpty }

    // MARK: Private state

    @ObservationIgnored private var onChange: (() -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var followUp: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// The decision that was applied, and a different one that has been seen once but not yet confirmed.
    @ObservationIgnored private var confirmedShow: Bool?
    @ObservationIgnored private var pendingShow: Bool?
    @ObservationIgnored private var seenText = ""
    @ObservationIgnored private var reasonText = ""
    /// The app that was in front before Gitzy. Used only when the window list cannot be read.
    @ObservationIgnored private var lastForegroundID: String?

    init() {
        let defaults = UserDefaults.standard
        isEnabled = defaults.bool(forKey: Self.enabledKey)
        if let saved = defaults.object(forKey: Self.thresholdKey) as? Double {
            threshold = Self.clamped(saved)
        }
        if let raw = defaults.string(forKey: Self.priorityKey), let saved = RulePriority(rawValue: raw) {
            priority = saved
        }
        rules = AppRuleStorage.decode(defaults.dictionary(forKey: Self.rulesKey))
    }

    /// BranchWidgetController calls this once. `onChange` runs whenever `allowsWidget` changes.
    func attach(onChange: @escaping () -> Void) {
        self.onChange = onChange
        settingsChanged()
    }

    // MARK: Changing settings

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        settingsChanged()
    }

    func setThreshold(_ value: Double) {
        threshold = Self.clamped(value)
        UserDefaults.standard.set(threshold, forKey: Self.thresholdKey)
        settingsChanged()
    }

    func setPriority(_ value: RulePriority) {
        priority = value
        UserDefaults.standard.set(value.rawValue, forKey: Self.priorityKey)
        settingsChanged()
    }

    func setRule(_ rule: AppRule, for appID: String) {
        guard !appID.isEmpty else { return }
        rules[appID] = rule
        saveRules()
    }

    func removeRule(for appID: String) {
        rules[appID] = nil
        saveRules()
    }

    private func saveRules() {
        UserDefaults.standard.set(AppRuleStorage.encode(rules), forKey: Self.rulesKey)
        settingsChanged()
    }

    private static func clamped(_ value: Double) -> Double {
        min(max(value, thresholdRange.lowerBound), thresholdRange.upperBound)
    }

    // MARK: Starting and stopping

    /// Any change to the settings: start or stop, and decide again right away, without waiting for a second read.
    private func settingsChanged() {
        confirmedShow = nil
        pendingShow = nil
        if isActive {
            start()
            tick()
        } else {
            stop()
        }
    }

    private func start() {
        guard observers.isEmpty else { return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if front != Bundle.main.bundleIdentifier { lastForegroundID = front }

        // Things that change which windows are showing tell us at once, so a switch is not waiting for the timer.
        let center = NSWorkspace.shared.notificationCenter
        let changes: [Notification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
        ]
        for name in changes {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let activated = name == NSWorkspace.didActivateApplicationNotification ? app?.bundleIdentifier : nil
                guard let self else { return }
                Task { @MainActor in self.workspaceChanged(activated: activated) }
            })
        }
        // Nothing is read while the Mac sleeps.
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.stopTimer() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.startTimer()
                self.tick()
            }
        })
        startTimer()
    }

    private func stop() {
        stopTimer()
        followUp?.cancel()
        followUp = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
        seenText = ""
        reasonText = ""
        rebuildStatus()
        if !allowsWidget {
            allowsWidget = true
            onChange?()
        }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
        timer.tolerance = 0.2   // lets macOS batch this with other wake-ups
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func workspaceChanged(activated: String?) {
        if let activated, activated != Bundle.main.bundleIdentifier {
            lastForegroundID = activated
        }
        // Read now, and once more shortly after: the second read is the one that confirms a change.
        tick()
        followUp?.cancel()
        followUp = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self.tick()
        }
    }

    // MARK: Reading and deciding

    private struct Evaluation {
        let decision: VisibilityDecision
        let seen: String
    }

    private func tick() {
        guard isActive else { return }
        let evaluation = evaluate()
        let wanted = evaluation.decision.showWidget

        if confirmedShow == nil || confirmedShow == wanted {
            pendingShow = nil
            commit(evaluation)
        } else if pendingShow == wanted {
            pendingShow = nil
            commit(evaluation)       // seen twice in a row
        } else {
            pendingShow = wanted     // seen once; wait for the next read
            seenText = evaluation.seen
            rebuildStatus()
        }
    }

    private func commit(_ evaluation: Evaluation) {
        confirmedShow = evaluation.decision.showWidget
        seenText = evaluation.seen
        reasonText = "Widget \(evaluation.decision.showWidget ? "shown" : "hidden"): \(evaluation.decision.reason)"
        rebuildStatus()
        if allowsWidget != evaluation.decision.showWidget {
            allowsWidget = evaluation.decision.showWidget
            onChange?()
        }
    }

    private func rebuildStatus() {
        let line = seenText.isEmpty ? "" : seenText + "\n" + reasonText
        if statusLine != line { statusLine = line }
    }

    private func evaluate() -> Evaluation {
        // The widget sits on the first screen, the one with the menu bar.
        let display = CGDisplayBounds(CGMainDisplayID())
        let reading = WindowSnapshot.read(
            display: display,
            ownPID: ProcessInfo.processInfo.processIdentifier,
            appID: { pid in NSRunningApplication(processIdentifier: pid)?.bundleIdentifier }
        )

        switch reading {
        case .windows(let windows):
            let apps = WindowCoverage.apps(in: windows, minFraction: threshold, minVisibleArea: Self.minimumVisibleArea)
            let visible = apps.filter { $0.isVisible }
            let decision = VisibilityRules.decide(
                visible: visible.map { $0.appID },
                rules: rules,
                priority: priority,
                name: { AppIdentity.name(for: $0) }
            )
            return Evaluation(decision: decision, seen: Self.describe(visible))

        case .unreadable:
            // macOS did not say where the windows are. Only the front app is known.
            let front = lastForegroundID.map { [$0] } ?? []
            let decision = VisibilityRules.decide(
                visible: front,
                rules: rules,
                priority: priority,
                name: { AppIdentity.name(for: $0) }
            )
            let name = lastForegroundID.map { AppIdentity.name(for: $0) } ?? "none"
            return Evaluation(decision: decision, seen: "The window list is unavailable, so only the front app counts (\(name)).")
        }
    }

    private static func describe(_ visible: [AppCoverage]) -> String {
        guard !visible.isEmpty else { return "No app windows are visible." }
        let shown = visible.prefix(6).map { app in
            "\(AppIdentity.name(for: app.appID)) \(Int((app.fraction * 100).rounded()))%"
        }
        let more = visible.count > 6 ? " and \(visible.count - 6) more" : ""
        return "Visible now: " + shown.joined(separator: ", ") + more + "."
    }
}
