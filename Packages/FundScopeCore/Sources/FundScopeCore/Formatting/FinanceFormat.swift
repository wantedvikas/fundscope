import Foundation

/// One place for number and date formatting (docs/04-design-system.md §Number formatting).
public enum FinanceFormat {
    static let india = Locale(identifier: "en_IN")

    /// ₹1,23,456.78
    public static func currency(_ value: Decimal, fractionDigits: Int = 2, signed: Bool = false) -> String {
        let style = Decimal.FormatStyle.Currency(code: "INR", locale: india)
            .precision(.fractionLength(fractionDigits))
            .sign(strategy: signed ? .always() : .automatic)
        // A true minus sign, matching percentages and points.
        return value.formatted(style).replacingOccurrences(of: "-", with: "−")
    }

    /// ₹1.23 L, ₹4.56 Cr — for tight spaces.
    public static func compactCurrency(_ value: Decimal, signed: Bool = false) -> String {
        let magnitude = abs(value)
        let sign = value < 0 ? "−" : (signed && value > 0 ? "+" : "")
        let body: String
        if magnitude >= 10_000_000 {
            body = "₹" + plain(magnitude / 10_000_000, digits: 2) + " Cr"
        } else if magnitude >= 100_000 {
            body = "₹" + plain(magnitude / 100_000, digits: 2) + " L"
        } else {
            body = currency(magnitude, fractionDigits: 0)
        }
        return sign + body
    }

    /// NAV with 4 decimals: 123.4567
    public static func nav(_ value: Decimal) -> String { plain(value, digits: 4) }

    /// Units with 3 decimals: 1,234.567
    public static func units(_ value: Decimal) -> String { plain(value, digits: 3) }

    /// +1.23% / −1.23%
    public static func percent(_ value: Decimal, digits: Int = 2, signed: Bool = true) -> String {
        // Sign follows the rounded value, so -0.001 shows as 0.00%, not −0.00%.
        let rounded = value.rounded(digits)
        let text = plain(abs(rounded), digits: digits) + "%"
        if rounded < 0 { return "−" + text }
        return signed && rounded > 0 ? "+" + text : text
    }

    /// Whole rupees: ₹1,23,457
    public static func wholeCurrency(_ value: Decimal, signed: Bool = false) -> String {
        currency(value.rounded(0), fractionDigits: 0, signed: signed)
    }

    /// Basis points with sign: +12.3 bps
    public static func bps(percentPoints value: Decimal) -> String {
        let bps = value * 100
        let text = plain(abs(bps), digits: 1) + " bps"
        if bps < 0 { return "−" + text }
        return bps > 0 ? "+" + text : text
    }

    /// Index points: 22,960.35, signed as +23.60 / −23.60.
    public static func points(_ value: Decimal, signed: Bool = false) -> String {
        let rounded = value.rounded(2)
        let text = plain(abs(rounded), digits: 2)
        if rounded < 0 { return "−" + text }
        return signed && rounded > 0 ? "+" + text : text
    }

    public static func plain(_ value: Decimal, digits: Int) -> String {
        value.formatted(.number.locale(india).precision(.fractionLength(digits)))
    }

    // MARK: Dates (IST)

    public static func date(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: india, timeZone: MarketCalendar.ist)
            .day(.twoDigits).month(.abbreviated).year())
    }

    public static func shortDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: india, timeZone: MarketCalendar.ist).day(.twoDigits).month(.abbreviated))
    }

    public static func time(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: india, timeZone: MarketCalendar.ist)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    public static func timeWithSeconds(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: india, timeZone: MarketCalendar.ist)
            .hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
    }

    public static func month(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(locale: india, timeZone: MarketCalendar.ist).month(.abbreviated).year())
    }
}
