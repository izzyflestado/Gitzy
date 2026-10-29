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
    /// 1 is the normal size. Text, icon and padding all follow it.
    var scale: CGFloat = 1
    /// Tint for the background. Nil keeps the plain, untinted look.
    var background: Color?
    /// Colour of the text and icon. Nil keeps the default soft white.
    var textColor: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// How strongly a chosen colour tints the glass. Full strength would hide the glass; this keeps it see-through.
    private static let tintStrength = 0.6

    private let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)

    var body: some View {
        styled
            .overlay(rim)
            .transaction { $0.animation = nil }
    }

    // Reduce Transparency turns the glass into a material.
    private var effectiveBackdrop: WidgetBackdrop {
        reduceTransparency && backdrop == .glass ? .material : backdrop
    }
    
    /// A soft highlight across the top-left, like light falling on glass. It sits behind the text, so the text stays crisp.
    private var sheen: some View {
        shape.fill(
            LinearGradient(
                colors: [Color.white.opacity(0.14), Color.white.opacity(0)],
                startPoint: .topLeading,
                endPoint: UnitPoint(x: 0.6, y: 0.7)
            )
        )
    }

    /// A thin bright edge, strongest at the top-left and bottom-right where light would catch it.
    private var rim: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [Color.white.opacity(0.75), Color.white.opacity(0.06), Color.white.opacity(0.06), Color.white.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            lineWidth: 1
        )
    }

    @ViewBuilder
    private var styled: some View {
        switch effectiveBackdrop {
        case .glass:
            label
                .background(shape.fill(background?.opacity(Self.tintStrength) ?? Color.clear))
                .glassEffect(.regular, in: shape)
        case .material:
            label
                .background(shape.fill((background ?? .clear).opacity(0.35)))
                .background(.ultraThinMaterial, in: shape)
        case .flat:
            label
                .background(shape.fill(background?.opacity(0.85) ?? Color.black.opacity(0.55)))
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
    }

    private var label: some View {
        HStack(spacing: 5 * scale) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 10 * scale, weight: .medium))
            Text(branch)
                .font(.system(size: 11 * scale, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(textColor ?? Color.primary.opacity(0.85))
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 6 * scale)
        .frame(maxWidth: 240 * scale)
        .background(sheen)
    }
}
