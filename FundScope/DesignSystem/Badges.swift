import FundScopeCore
import SwiftUI

/// Small tinted label for tags and badges.
struct Pill: View {
    let text: String
    var tint: Color = Palette.textSecondary
    var symbol: String?

    var body: some View {
        HStack(spacing: Space.xxs) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .textStyle(.label, color: tint)
        .padding(.horizontal, Space.xs - 2)
        .padding(.vertical, 2)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Radius.small))
    }

    static func estimateStatus(_ status: NAVEstimator.Status) -> Pill {
        switch status {
        case .ok: Pill(text: "Estimated", tint: Palette.estimated)
        case .lowCoverage: Pill(text: "Low coverage", tint: Palette.warning, symbol: "exclamationmark.triangle")
        case .notEstimable: Pill(text: "Not estimable", tint: Palette.textSecondary)
        }
    }
}

struct DemoBadge: View {
    var body: some View {
        Pill(text: "Demo data", tint: Palette.warning, symbol: "flask")
            .help("Fictional funds, companies and prices for exploring the app. Never mixed with real data.")
    }
}

/// Says whether a figure is official (AMFI) or estimated (model).
enum FigureSource {
    case official(Date?)
    case estimated(Date?)
    case previousSession(Date?)
    /// Date of the fund portfolio disclosure a figure is based on.
    case holdings(Date)

    var text: String {
        switch self {
        case .official(let d): d.map { "Official · \(FinanceFormat.shortDate($0))" } ?? "Official"
        case .estimated(let d): d.map { "Est. · \(FinanceFormat.time($0))" } ?? "Est."
        case .previousSession(let d): d.map { "Last session · \(FinanceFormat.shortDate($0))" } ?? "Last session"
        case .holdings(let d): "Holdings · \(FinanceFormat.shortDate(d))"
        }
    }

    var tint: Color {
        switch self {
        case .official, .holdings: Palette.textSecondary
        case .estimated: Palette.estimated
        case .previousSession: Palette.warning
        }
    }
}

struct SourceTag: View {
    let source: FigureSource

    var body: some View {
        Text(source.text).textStyle(.caption, color: source.tint)
    }
}

struct StatusDot: View {
    let status: ProviderStatus

    private var color: Color {
        switch status {
        case .connected: Palette.positive
        case .updating: Palette.accent
        case .stale, .importRequired: Palette.warning
        case .authRequired, .unavailable: Palette.negative
        }
    }

    var body: some View {
        HStack(spacing: Space.xxs + 2) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(status.label).textStyle(.label, color: Palette.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct MarketStatusBadge: View {
    let status: MarketStatus

    var body: some View {
        Pill(text: status.label, tint: status == .open ? Palette.positive : Palette.textSecondary,
             symbol: status == .open ? "circle.fill" : "moon")
    }
}
