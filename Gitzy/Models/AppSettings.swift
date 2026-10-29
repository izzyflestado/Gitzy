import AppKit

/// User settings stored in UserDefaults. The GitHub token is NOT here; it lives only in its own private file (see TokenFile).
@Observable
final class AppSettings {
    private static let terminalKey = "terminalAppPath"
    private static let refreshKey = "refreshIntervalMinutes"
    private static let positionKey = "widgetPosition"
    private static let scaleKey = "widgetScale"
    private static let backgroundKey = "widgetBackground"
    private static let textColorKey = "widgetTextColor"
    private static let builtInTerminalID = "com.apple.Terminal"

    /// Minutes between automatic GitHub refreshes. 0 means manual only.
    static let refreshOptions = [15, 30, 60, 0]

    /// How much smaller or bigger than normal (1.0) the branch widget can be made.
    static let widgetScaleRange: ClosedRange<Double> = 0.75...1.75

    static func intervalLabel(_ minutes: Int) -> String {
        minutes == 0 ? "Manual only" : "\(minutes) min"
    }

    private(set) var terminalAppPath: String?
    private(set) var refreshIntervalMinutes = 30
    private(set) var widgetPosition: WidgetPosition = .topRight
    private(set) var widgetScale = 1.0
    /// Tint of the widget's glass. Nil means the plain, untinted glass.
    private(set) var widgetBackground: RGBAColor?
    /// Colour of the widget's text. Nil means the default (soft white).
    private(set) var widgetTextColor: RGBAColor?

    init() {
        terminalAppPath = UserDefaults.standard.string(forKey: Self.terminalKey)
        if let saved = UserDefaults.standard.object(forKey: Self.refreshKey) as? Int,
           Self.refreshOptions.contains(saved) {
            refreshIntervalMinutes = saved
        }
        if let raw = UserDefaults.standard.string(forKey: Self.positionKey),
           let saved = WidgetPosition(rawValue: raw) {
            widgetPosition = saved
        }
        if let saved = UserDefaults.standard.object(forKey: Self.scaleKey) as? Double {
            widgetScale = Self.clampedScale(saved)
        }
        widgetBackground = UserDefaults.standard.string(forKey: Self.backgroundKey).flatMap { RGBAColor(hex: $0) }
        widgetTextColor = UserDefaults.standard.string(forKey: Self.textColorKey).flatMap { RGBAColor(hex: $0) }
    }

    func setRefreshInterval(_ minutes: Int) {
        guard Self.refreshOptions.contains(minutes) else { return }
        refreshIntervalMinutes = minutes
        UserDefaults.standard.set(minutes, forKey: Self.refreshKey)
    }

    func setWidgetPosition(_ position: WidgetPosition) {
        widgetPosition = position
        UserDefaults.standard.set(position.rawValue, forKey: Self.positionKey)
    }

    func setWidgetScale(_ value: Double) {
        let clamped = Self.clampedScale(value)
        widgetScale = clamped
        UserDefaults.standard.set(clamped, forKey: Self.scaleKey)
    }

    /// Pass nil to go back to the plain glass.
    func setWidgetBackground(_ color: RGBAColor?) {
        widgetBackground = color
        Self.save(color, forKey: Self.backgroundKey)
    }

    /// Pass nil to go back to the default text colour.
    func setWidgetTextColor(_ color: RGBAColor?) {
        widgetTextColor = color
        Self.save(color, forKey: Self.textColorKey)
    }

    /// Size and both colours back to how they came. The position is not part of this.
    func resetWidgetAppearance() {
        setWidgetScale(1)
        setWidgetBackground(nil)
        setWidgetTextColor(nil)
    }

    /// Pass nil to go back to Apple's Terminal.
    func setTerminalApp(_ url: URL?) {
        terminalAppPath = url?.path
        UserDefaults.standard.set(url?.path, forKey: Self.terminalKey)
    }

    /// The chosen terminal, or Apple's Terminal when none is chosen or the chosen app no longer exists.
    var terminalAppURL: URL? {
        if let path = terminalAppPath, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.builtInTerminalID)
    }

    var terminalName: String {
        terminalAppURL?.deletingPathExtension().lastPathComponent ?? "none found"
    }

    // MARK: Private

    private static func clampedScale(_ value: Double) -> Double {
        min(max(value, widgetScaleRange.lowerBound), widgetScaleRange.upperBound)
    }

    private static func save(_ color: RGBAColor?, forKey key: String) {
        if let color {
            UserDefaults.standard.set(color.hex, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
