import SwiftUI

/// A colour as plain numbers, so it can be saved in UserDefaults as text and compared exactly.
/// Components are 0...1 in the sRGB colour space.
nonisolated struct RGBAColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    /// "RRGGBBAA", with or without a leading "#". Anything else gives nil.
    init?(hex text: String) {
        var digits = text.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 8, digits.allSatisfy(\.isHexDigit), let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 24) & 0xFF) / 255,
            green: Double((value >> 16) & 0xFF) / 255,
            blue: Double((value >> 8) & 0xFF) / 255,
            alpha: Double(value & 0xFF) / 255
        )
    }

    /// From hue, saturation and brightness, each 0...1. A hue of 1 is the same as 0 (round the wheel).
    init(hue: Double, saturation: Double, brightness: Double) {
        let scaled = (hue - hue.rounded(.down)) * 6
        let sector = Int(scaled.rounded(.down))
        let fraction = scaled - scaled.rounded(.down)
        let s = Self.clamp(saturation)
        let v = Self.clamp(brightness)
        let p = v * (1 - s)
        let q = v * (1 - s * fraction)
        let t = v * (1 - s * (1 - fraction))
        switch sector {
        case 0: self.init(red: v, green: t, blue: p)
        case 1: self.init(red: q, green: v, blue: p)
        case 2: self.init(red: p, green: v, blue: t)
        case 3: self.init(red: p, green: q, blue: v)
        case 4: self.init(red: t, green: p, blue: v)
        default: self.init(red: v, green: p, blue: q)
        }
    }

    /// "RRGGBBAA" in capitals, the form that is saved.
    var hex: String {
        func byte(_ component: Double) -> UInt32 { UInt32((component * 255).rounded()) }
        return String(format: "%02X%02X%02X%02X", byte(red), byte(green), byte(blue), byte(alpha))
    }

    /// Hue, saturation and brightness, each 0...1. A grey has no real hue, so it reports 0.
    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let high = max(red, green, blue)
        let low = min(red, green, blue)
        let delta = high - low
        var hue = 0.0
        if delta > 0 {
            if high == red {
                hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
            } else if high == green {
                hue = (blue - red) / delta + 2
            } else {
                hue = (red - green) / delta + 4
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, high == 0 ? 0 : delta / high, high)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
