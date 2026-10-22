import SwiftUI
import AppKit

/// Panel colour scheme. All dark themes sit on a vibrancy material with a tint wash on top.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let dark: Bool
    /// Wash painted over the blur material.
    let tint: Color
    let tintOpacity: Double
    let accent: Color
    let text: Color
    let secondary: Color
    let tertiary: Color
    let hairline: Color
    let selection: Color
    let hover: Color
    let field: Color

    static func dark(_ id: String, _ name: String, tint: Color, accent: Color, tintOpacity: Double = 0.72) -> Theme {
        Theme(id: id, name: name, dark: true, tint: tint, tintOpacity: tintOpacity, accent: accent,
              text: Color(white: 0.94), secondary: Color(white: 0.70), tertiary: Color(white: 0.52),
              hairline: Color.white.opacity(0.08), selection: accent.opacity(0.26), hover: Color.white.opacity(0.045),
              field: Color.white.opacity(0.055))
    }

    static let graphite = dark("graphite", "Graphite", tint: Color(red: 0.10, green: 0.105, blue: 0.115),
                               accent: Color(red: 0.47, green: 0.62, blue: 1.0))
    static let midnight = dark("midnight", "Midnight", tint: Color(red: 0.05, green: 0.08, blue: 0.15),
                               accent: Color(red: 0.25, green: 0.85, blue: 0.80))
    static let forest = dark("forest", "Forest", tint: Color(red: 0.06, green: 0.11, blue: 0.09),
                             accent: Color(red: 0.45, green: 0.88, blue: 0.55))
    static let rose = dark("rose", "Rose", tint: Color(red: 0.13, green: 0.07, blue: 0.10),
                           accent: Color(red: 1.0, green: 0.50, blue: 0.66))
    static let oled = Theme(id: "oled", name: "Black", dark: true, tint: .black, tintOpacity: 0.94,
                            accent: Color(red: 1.0, green: 0.62, blue: 0.25), text: Color(white: 0.95), secondary: Color(white: 0.58),
                            tertiary: Color(white: 0.50), hairline: Color.white.opacity(0.09), selection: Color.white.opacity(0.13),
                            hover: Color.white.opacity(0.05), field: Color.white.opacity(0.06))
    static let light = Theme(id: "light", name: "Light", dark: false, tint: Color(white: 0.985), tintOpacity: 0.78,
                             accent: Color(red: 0.16, green: 0.42, blue: 0.98), text: Color(white: 0.10), secondary: Color(white: 0.40),
                             tertiary: Color(white: 0.58), hairline: Color.black.opacity(0.08), selection: Color(red: 0.16, green: 0.42, blue: 0.98).opacity(0.16),
                             hover: Color.black.opacity(0.04), field: Color.black.opacity(0.045))

    static let all: [Theme] = [graphite, midnight, forest, rose, oled, light]
}
