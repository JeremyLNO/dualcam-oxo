import SwiftUI

/// DualCam OxO design tokens.
/// A dark, camera-first look on Crazy Bee Labs' black + honey brand.
enum Palette {
    // Brand — honey
    static let honey     = Color(red: 0.949, green: 0.698, blue: 0.110)   // #F2B21C
    static let honeyDeep = Color(red: 0.839, green: 0.588, blue: 0.063)   // #D69610
    static let honeySoft = Color(red: 0.949, green: 0.698, blue: 0.110).opacity(0.16)

    // Surfaces — near-black
    static let bg0   = Color(red: 0.055, green: 0.055, blue: 0.063)        // #0E0E10
    static let bg1   = Color(red: 0.086, green: 0.086, blue: 0.098)        // #161619
    static let panel = Color(red: 0.129, green: 0.129, blue: 0.145)        // #212125
    static let hair  = Color(red: 0.235, green: 0.235, blue: 0.255)        // separators

    // Text
    static let ink   = Color(red: 0.965, green: 0.965, blue: 0.976)        // near-white
    static let sub   = Color(red: 0.62, green: 0.63, blue: 0.67)
    static let faint = Color(red: 0.44, green: 0.45, blue: 0.49)

    // Semantic
    static let record  = Color(red: 0.94, green: 0.26, blue: 0.28)         // shutter red
    static let success = Color(red: 0.24, green: 0.78, blue: 0.52)
    static let danger  = Color(red: 0.93, green: 0.32, blue: 0.34)

    // Background gradient (settings / sheets)
    static let bg: [Color] = [bg1, bg0]

    static let honeyGradient: [Color] = [
        Color(red: 0.98, green: 0.76, blue: 0.22),
        Color(red: 0.86, green: 0.60, blue: 0.06)
    ]
}

extension LinearGradient {
    static let honey = LinearGradient(colors: Palette.honeyGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
    static let appBackground = LinearGradient(colors: Palette.bg, startPoint: .top, endPoint: .bottom)
}
