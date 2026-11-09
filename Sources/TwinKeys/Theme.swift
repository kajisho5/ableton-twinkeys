#if os(macOS)
import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    /// A color that follows the system appearance (light / dark).
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

/// All colors and sizes in one place. Contrast ratios are listed in docs/design.md (3.5).
enum Theme {
    static let windowBackground = Color.dynamic(light: 0xECECEC, dark: 0x1F1F21)
    static let groupBackground = Color.dynamic(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let separator = Color.dynamic(light: 0xD1D1D6, dark: 0x3D3D40)
    static let textPrimary = Color.dynamic(light: 0x1D1D1F, dark: 0xF2F2F7)
    static let textSecondary = Color.dynamic(light: 0x5F5F64, dark: 0xAEAEB2)
    static let accent = Color.dynamic(light: 0x0060C7, dark: 0x5AA9FF)
    static let accentFill = Color.dynamic(light: 0x0060C7, dark: 0x1A66CC)
    static let ok = Color.dynamic(light: 0x1B7A31, dark: 0x4FD06A)
    static let warning = Color.dynamic(light: 0x8A5A00, dark: 0xF2B13A)
    static let dangerFill = Color.dynamic(light: 0xC0241A, dark: 0xC0241A)
    static let selectedRow = Color.dynamic(light: 0xDCE9FA, dark: 0x23364F)
    static let buttonBackground = Color.dynamic(light: 0xFFFFFF, dark: 0x3A3A3C)
    static let buttonHover = Color.dynamic(light: 0xF0F0F2, dark: 0x48484A)
    static let buttonPressed = Color.dynamic(light: 0xE2E2E6, dark: 0x545458)
    static let buttonBorder = Color.dynamic(light: 0x8E8E93, dark: 0x7C7C80)   // ≥ 3:1 against the group background
    static let idleDot = Color.dynamic(light: 0x6E6E73, dark: 0x8E8E93)

    static let body: CGFloat = 13
    static let caption: CGFloat = 11
    static let value: CGFloat = 17
    static let controlHeight: CGFloat = 28
    static let outerPadding: CGFloat = 16
    static let groupSpacing: CGFloat = 18
    static let groupRadius: CGFloat = 8
    static let buttonRadius: CGFloat = 6
    static let minWindow = CGSize(width: 440, height: 330)
}
#endif
