import AppKit
import FundScopeCore
import SwiftUI

// Design tokens. Spec: docs/04-design-system.md. Feature views use only these values.

enum Space {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let s: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 40
}

enum Radius {
    static let small: CGFloat = 4
    static let medium: CGFloat = 6
    static let large: CGFloat = 10
}

enum Metrics {
    static let tableRow: CGFloat = 24
    static let chartHeight: CGFloat = 220
    static let inspectorWidth: CGFloat = 300
    static let windowMinWidth: CGFloat = 1000
    static let windowMinHeight: CGFloat = 640
}

enum Palette {
    static let textPrimary = Color(nsColor: .labelColor)
    static let textSecondary = Color(nsColor: .secondaryLabelColor)
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surfaceElevated = Color(nsColor: .controlBackgroundColor)
    static let borderSubtle = Color(nsColor: .separatorColor)
    static let accent = Color.accentColor
    static let warning = Color(nsColor: .systemOrange)
    static let disabled = Color(nsColor: .disabledControlTextColor)
    static let selected = Color(nsColor: .selectedContentBackgroundColor)
    static let fill = Color(nsColor: .quaternaryLabelColor)

    // Desaturated so gains/losses don't dominate the screen; lighter in dark mode for contrast.
    static let positive = dynamic(light: (0.10, 0.52, 0.30), dark: (0.30, 0.78, 0.50))
    static let negative = dynamic(light: (0.78, 0.22, 0.22), dark: (0.96, 0.42, 0.40))
    static let estimated = dynamic(light: (0.30, 0.38, 0.78), dark: (0.55, 0.62, 1.00))

    /// Categorical series colours for charts, checked in both appearances.
    static let series: [Color] = [
        dynamic(light: (0.20, 0.42, 0.85), dark: (0.40, 0.60, 1.00)),
        dynamic(light: (0.85, 0.50, 0.12), dark: (1.00, 0.65, 0.30)),
        dynamic(light: (0.20, 0.62, 0.55), dark: (0.35, 0.80, 0.72)),
        dynamic(light: (0.62, 0.32, 0.75), dark: (0.78, 0.55, 0.92)),
        dynamic(light: (0.55, 0.55, 0.58), dark: (0.68, 0.68, 0.72)),
    ]

    static func direction(_ value: Decimal?) -> Color {
        guard let value else { return textPrimary }
        return value > 0 ? positive : value < 0 ? negative : textPrimary
    }

    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}

enum TextStyle {
    case screenTitle, sectionTitle, cardTitle, body, secondary, table, label, caption, metricValue, metricValueSmall

    var font: Font {
        switch self {
        case .screenTitle: .system(size: 22, weight: .semibold)
        case .sectionTitle: .system(size: 13, weight: .semibold)
        case .cardTitle: .system(size: 10, weight: .semibold)
        case .body, .secondary: .system(size: 13)
        case .table: .system(size: 12)
        case .label: .system(size: 11, weight: .medium)
        case .caption: .system(size: 11)
        case .metricValue: .system(size: 22, weight: .medium)
        case .metricValueSmall: .system(size: 15, weight: .medium)
        }
    }

    var color: Color {
        switch self {
        case .secondary, .cardTitle: Palette.textSecondary
        case .caption: Palette.textTertiary
        default: Palette.textPrimary
        }
    }
}

extension View {
    /// Applies a design-system text style. Digits are always monospaced so numbers line up.
    /// Pass a different colour here: a `.foregroundStyle` added afterwards can't override the style's own
    /// (the innermost one wins), which is how green/red and secondary greys were lost before.
    func textStyle(_ style: TextStyle, color: Color? = nil) -> some View {
        font(style.font)
            .monospacedDigit()
            .foregroundStyle(color ?? style.color)
            .textCase(style == .cardTitle ? .uppercase : nil)
            .tracking(style == .cardTitle ? 0.5 : 0)
    }

    /// 1px hairline border with the standard radius.
    func hairlineBorder(radius: CGFloat = Radius.medium) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.borderSubtle))
    }
}

extension Decimal {
    var cg: CGFloat { CGFloat(double) }
}
