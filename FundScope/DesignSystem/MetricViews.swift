import FundScopeCore
import SwiftUI

/// One summary figure: label, value, optional delta and source tag.
struct MetricTile: View {
    let label: String
    let value: Decimal?
    var kind: ValueText.Kind = .wholeCurrency
    var colored = false
    var delta: Decimal?
    var deltaKind: ValueText.Kind = .percent
    var source: FigureSource?
    var missingReason = "Not available"
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(label).textStyle(.cardTitle)
            ValueText(value: value, kind: kind, colored: colored,
                      style: compact ? .metricValueSmall : .metricValue, missingReason: missingReason)
                .minimumScaleFactor(0.7)
            HStack(spacing: Space.xs) {
                if let delta { ValueText(value: delta, kind: deltaKind, colored: true, style: .label) }
                if let source { SourceTag(source: source) }
            }
            .frame(minHeight: 14, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Row of metrics divided by hairlines (no cards).
struct MetricStrip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { index, subview in
                    if index > 0 {
                        Rectangle().fill(Palette.borderSubtle).frame(width: 1).padding(.horizontal, Space.m)
                    }
                    subview
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, Space.m)
        .overlay(alignment: .top) { Rectangle().fill(Palette.borderSubtle).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.borderSubtle).frame(height: 1) }
    }
}

/// Horizontal bar list for allocations and exposures.
struct BarList: View {
    struct Item: Identifiable {
        let id: String
        let label: String
        /// Percent share, 0…100.
        let share: Decimal
        var value: Decimal?
        var muted = false
    }

    let items: [Item]
    var maxItems = 8
    var tint: Color = Palette.series[0]

    var body: some View {
        let shown = Array(items.prefix(maxItems))
        let maxShare = shown.map(\.share).max() ?? 1
        Grid(alignment: .leading, horizontalSpacing: Space.s, verticalSpacing: Space.xs) {
            ForEach(shown) { item in
                GridRow {
                    Text(item.label).textStyle(.table, color: item.muted ? Palette.textSecondary : Palette.textPrimary)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(minWidth: 120, maxWidth: 220, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(item.muted ? Palette.fill : tint)
                            .frame(width: max(2, geo.size.width * (maxShare == 0 ? 0 : item.share / maxShare).cg))
                    }
                    .frame(height: 6)
                    ValueText(value: item.share, kind: .percent)
                        .gridColumnAlignment(.trailing)
                    if let value = item.value {
                        ValueText(value: value, kind: .compactCurrency, color: Palette.textSecondary, style: .table)
                            .gridColumnAlignment(.trailing)
                    }
                }
            }
            if items.count > maxItems {
                GridRow {
                    Text("+ \(items.count - maxItems) more").textStyle(.caption)
                }
            }
        }
    }
}

/// How much of the fund the estimate is based on.
struct CoverageMeter: View {
    let estimate: NAVEstimator.Estimate
    var showLegend = true

    var body: some View {
        let total = max(estimate.pricedWeight + estimate.flatWeight + estimate.unpricedWeight + estimate.unsupportedWeight, 1)
        let parts: [(String, Decimal, Color)] = [
            ("Live prices", estimate.pricedWeight, Palette.estimated),
            ("Cash & debt (flat)", estimate.flatWeight, Palette.series[4]),
            ("Unpriced", estimate.unpricedWeight, Palette.warning),
            ("Unsupported", estimate.unsupportedWeight, Palette.negative),
        ]
        VStack(alignment: .leading, spacing: Space.xs) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(parts, id: \.0) { part in
                        if part.1 > 0 {
                            Rectangle().fill(part.2).frame(width: geo.size.width * (part.1 / total).cg)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 6)
            if showLegend {
                HStack(spacing: Space.m) {
                    ForEach(parts, id: \.0) { part in
                        HStack(spacing: Space.xxs) {
                            Circle().fill(part.2).frame(width: 6, height: 6)
                            Text(part.0).textStyle(.caption)
                            ValueText(value: part.1, kind: .percent, style: .caption)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coverage \(FinanceFormat.percent(estimate.coverage, signed: false))")
    }
}
