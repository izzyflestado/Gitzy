import SwiftUI

/// A colour wheel: drag on the disc to pick the hue (around) and the saturation (from the white centre outwards),
/// and use the slim slider under it for brightness. Drawn with shapes and gradients, no images.
///
/// `color` is nil while the setting is still at its default. The wheel then shows no marker, and the brightness
/// slider waits until a colour has been picked.
struct ColorWheelPicker: View {
    let title: String
    let color: RGBAColor?
    let onChange: (RGBAColor) -> Void

    private let diameter: CGFloat = 84

    // What the controls show. Kept separately because a grey or black colour has lost its hue and saturation,
    // and the marker should stay where the person left it while they slide the brightness around.
    @State private var hue: Double
    @State private var saturation: Double
    @State private var brightness: Double
    /// The last colour this wheel sent out, so an outside change (Reset) can be told apart from our own.
    @State private var lastSent: RGBAColor?

    init(title: String, color: RGBAColor?, onChange: @escaping (RGBAColor) -> Void) {
        self.title = title
        self.color = color
        self.onChange = onChange
        let start = color?.hsb ?? (hue: 0, saturation: 0, brightness: 1)
        _hue = State(initialValue: start.hue)
        _saturation = State(initialValue: start.saturation)
        _brightness = State(initialValue: start.brightness)
        _lastSent = State(initialValue: color)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            wheel

            Slider(value: Binding(get: { brightness }, set: { brightness = $0; send() }), in: 0...1)
                .controlSize(.mini)
                .frame(width: diameter)
                .disabled(color == nil)
                .accessibilityLabel("\(title) brightness")
        }
        .onChange(of: color) { _, newValue in
            // Our own change comes back as the same colour. Anything else came from outside.
            guard newValue != lastSent else { return }
            lastSent = newValue
            if let hsb = newValue?.hsb {
                hue = hsb.hue
                saturation = hsb.saturation
                brightness = hsb.brightness
            } else {
                hue = 0
                saturation = 0
                brightness = 1
            }
        }
        .transaction { $0.animation = nil }
    }

    // MARK: The wheel

    private var wheel: some View {
        ZStack {
            Circle().fill(AngularGradient(colors: Self.hueColors, center: .center))
            Circle().fill(RadialGradient(colors: [Color.white, Color.white.opacity(0)], center: .center, startRadius: 0, endRadius: diameter / 2))
            // Darkens the whole wheel as brightness goes down.
            Circle().fill(Color.black.opacity(1 - brightness))
            Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
            if let color {
                marker(for: color)
            }
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { pick(at: $0.location) }
        )
        .accessibilityElement()
        .accessibilityLabel("\(title) colour wheel")
    }

    private func marker(for color: RGBAColor) -> some View {
        let radius = diameter / 2
        let angle = hue * 2 * .pi
        return Circle()
            .fill(color.color)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
            .shadow(color: Color.black.opacity(0.4), radius: 1)
            .frame(width: 12, height: 12)
            .offset(x: cos(angle) * saturation * radius, y: sin(angle) * saturation * radius)
    }

    /// The first and last colour are both red, so the circle closes without a seam.
    private static let hueColors: [Color] = stride(from: 0.0, through: 1.0, by: 1.0 / 12).map {
        RGBAColor(hue: $0, saturation: 1, brightness: 1).color
    }

    // MARK: Picking

    private func pick(at point: CGPoint) {
        let radius = diameter / 2
        let dx = point.x - radius
        let dy = point.y - radius
        // The gradient starts at 3 o'clock and runs clockwise, which is also how y-down angles grow.
        var angle = atan2(dy, dx)
        if angle < 0 { angle += 2 * .pi }
        hue = angle / (2 * .pi)
        saturation = min(hypot(dx, dy) / radius, 1)
        // The first pick on a default wheel starts at full brightness, so the colour is visible straight away.
        if color == nil { brightness = 1 }
        send()
    }

    private func send() {
        let picked = RGBAColor(hue: hue, saturation: saturation, brightness: brightness)
        lastSent = picked
        onChange(picked)
    }
}
