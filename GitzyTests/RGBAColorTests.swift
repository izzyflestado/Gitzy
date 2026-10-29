import Foundation
import Testing
@testable import Gitzy

nonisolated struct RGBAColorTests {

    @Test func formatsAsEightCapitalHexDigits() {
        #expect(RGBAColor(red: 1, green: 0, blue: 0).hex == "FF0000FF")
        #expect(RGBAColor(red: 0, green: 0, blue: 0, alpha: 0).hex == "00000000")
        #expect(RGBAColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8).hex == "336699CC")
    }

    @Test func parsesWhatItFormats() throws {
        let color = try #require(RGBAColor(hex: "336699CC"))
        #expect(color.hex == "336699CC")
        #expect(color == RGBAColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8))
    }

    @Test func aLeadingHashAndSpacesAreAllowed() {
        #expect(RGBAColor(hex: "#336699CC") == RGBAColor(hex: "336699CC"))
        #expect(RGBAColor(hex: "  336699CC ") == RGBAColor(hex: "336699CC"))
        #expect(RGBAColor(hex: "336699cc") == RGBAColor(hex: "336699CC"))
    }

    @Test func badTextGivesNothing() {
        for text in ["", "#", "FFF", "336699", "336699CC00", "GG0000FF", "33 6699CC", "not a colour"] {
            #expect(RGBAColor(hex: text) == nil, "\(text)")
        }
    }

    @Test func everyByteSurvivesTheRoundTrip() throws {
        for value in stride(from: 0, through: 255, by: 5) {
            let text = String(format: "%02X%02X%02X%02X", UInt32(value), UInt32(255 - value), UInt32(value), UInt32(255))
            let color = try #require(RGBAColor(hex: text))
            #expect(color.hex == text, "\(text)")
        }
    }

    @Test func componentsAreKeptInsideZeroToOne() {
        let color = RGBAColor(red: -2, green: 5, blue: 0.5, alpha: 9)
        #expect(color.red == 0)
        #expect(color.green == 1)
        #expect(color.blue == 0.5)
        #expect(color.alpha == 1)
    }

    @Test func alphaDefaultsToFullyOpaque() {
        #expect(RGBAColor(red: 0, green: 0, blue: 0).alpha == 1)
    }

    // MARK: Hue, saturation, brightness

    @Test func theMainHuesGiveTheMainColours() {
        #expect(RGBAColor(hue: 0, saturation: 1, brightness: 1).hex == "FF0000FF")
        #expect(RGBAColor(hue: 1.0 / 6, saturation: 1, brightness: 1).hex == "FFFF00FF")
        #expect(RGBAColor(hue: 1.0 / 3, saturation: 1, brightness: 1).hex == "00FF00FF")
        #expect(RGBAColor(hue: 0.5, saturation: 1, brightness: 1).hex == "00FFFFFF")
        #expect(RGBAColor(hue: 2.0 / 3, saturation: 1, brightness: 1).hex == "0000FFFF")
        #expect(RGBAColor(hue: 5.0 / 6, saturation: 1, brightness: 1).hex == "FF00FFFF")
    }

    @Test func aHueOfOneIsTheSameAsZero() {
        #expect(RGBAColor(hue: 1, saturation: 1, brightness: 1) == RGBAColor(hue: 0, saturation: 1, brightness: 1))
    }

    @Test func noSaturationGivesGreyAndNoBrightnessGivesBlack() {
        #expect(RGBAColor(hue: 0.3, saturation: 0, brightness: 1).hex == "FFFFFFFF")
        #expect(RGBAColor(hue: 0.3, saturation: 0, brightness: 0.5).hex == "808080FF")
        #expect(RGBAColor(hue: 0.3, saturation: 1, brightness: 0).hex == "000000FF")
    }

    @Test func hsbComesBackAsPutIn() {
        for hue in stride(from: 0.0, to: 1.0, by: 0.05) {
            let result = RGBAColor(hue: hue, saturation: 0.6, brightness: 0.8).hsb
            #expect(abs(result.hue - hue) < 0.001, "hue \(hue)")
            #expect(abs(result.saturation - 0.6) < 0.001, "saturation at hue \(hue)")
            #expect(abs(result.brightness - 0.8) < 0.001, "brightness at hue \(hue)")
        }
    }

    @Test func aGreyReportsHueZeroAndNoSaturation() {
        let result = RGBAColor(red: 0.5, green: 0.5, blue: 0.5).hsb
        #expect(result.hue == 0)
        #expect(result.saturation == 0)
        #expect(result.brightness == 0.5)
    }

    @Test func blackReportsNoBrightness() {
        let result = RGBAColor(red: 0, green: 0, blue: 0).hsb
        #expect(result.saturation == 0)
        #expect(result.brightness == 0)
    }
}
