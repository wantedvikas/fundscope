import FundScopeCore
import SwiftUI

/// Formats every financial value the same way. Unknown values render as "—" with a reason.
struct ValueText: View {
    enum Kind { case currency, wholeCurrency, compactCurrency, nav, units, count, percent, bps, points }

    let value: Decimal?
    var kind: Kind = .currency
    var signed = false
    /// Decimal places for percentages.
    var digits = 2
    /// Tint green/red by sign (the sign is always shown too).
    var colored = false
    /// Tint by this direction instead of the value's own sign (a price coloured by its day's change).
    var direction: Decimal?
    /// A fixed colour (estimated values, secondary figures) when it isn't coloured by direction.
    var color: Color?
    var style: TextStyle = .table
    var missingReason = "Not available"

    var body: some View {
        if let value {
            Text(Self.format(value, kind: kind, signed: signed || colored, digits: digits))
                .textStyle(style, color: colored ? Palette.direction(value) : direction.map(Palette.direction) ?? color ?? style.color)
                .lineLimit(1)
        } else {
            MissingValue(reason: missingReason).textStyle(style)
        }
    }

    static func format(_ value: Decimal, kind: Kind, signed: Bool = false, digits: Int = 2) -> String {
        switch kind {
        case .currency: FinanceFormat.currency(value, signed: signed)
        case .wholeCurrency: FinanceFormat.wholeCurrency(value, signed: signed)
        case .count: FinanceFormat.plain(value, digits: 0)
        case .compactCurrency: FinanceFormat.compactCurrency(value, signed: signed)
        case .nav: FinanceFormat.nav(value)
        case .units: FinanceFormat.units(value)
        case .percent: FinanceFormat.percent(value, digits: digits, signed: signed)
        case .bps: FinanceFormat.bps(percentPoints: value)
        case .points: FinanceFormat.points(value, signed: signed)
        }
    }
}

/// "—" placeholder for values that are unknown. Never shown as zero.
struct MissingValue: View {
    let reason: String

    var body: some View {
        Text("—")
            .foregroundStyle(Palette.textTertiary)
            .help(reason)
            .accessibilityLabel("Unavailable. \(reason)")
    }
}
