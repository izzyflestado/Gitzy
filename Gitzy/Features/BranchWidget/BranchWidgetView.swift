import SwiftUI

/// The three looks from the spec, in fallback order: glass, then material, then a flat dark fill.
/// Glass is the look; the other two are what it falls back to.
enum WidgetBackdrop: String, CaseIterable, Identifiable {
    case glass, material, flat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .glass: return "Glass"
        case .material: return "Material"
        case .flat: return "Flat"
        }
    }
}

struct BranchWidgetView: View {
    let branch: String
    let backdrop: WidgetBackdrop

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        styled
            .transaction { $0.animation = nil }
    }

    // Reduce Transparency turns the glass into a material.
    private var effectiveBackdrop: WidgetBackdrop {
        reduceTransparency && backdrop == .glass ? .material : backdrop
    }

    @ViewBuilder
    private var styled: some View {
        switch effectiveBackdrop {
        case .glass:
            label.glassEffect(.regular, in: shape)
        case .material:
            label.background(.ultraThinMaterial, in: shape)
        case .flat:
            label
                .background(shape.fill(Color.black.opacity(0.55)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
    }

    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10, weight: .medium))
            Text(branch)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(Color.primary.opacity(0.85))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 240)
    }
}
