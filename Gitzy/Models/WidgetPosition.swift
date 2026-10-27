import Foundation

/// Where the branch widget sits on the main display.
nonisolated enum WidgetPosition: String, CaseIterable, Identifiable, Sendable {
    case notch, topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var label: String {
        switch self {
        case .notch: return "Notch"
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }
}
