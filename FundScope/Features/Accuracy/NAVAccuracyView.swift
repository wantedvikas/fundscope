import Charts
import FundScopeCore
import SwiftUI

struct NAVAccuracyView: View {
    @Environment(AppModel.self) private var model
    @State private var fundCode = ""

    var body: some View {
        if let data = model.data, data.reconciliations.isEmpty {
            let pending = model.pendingReconciliations
            EmptyState(symbol: "scope", title: pending.isEmpty ? "No reconciliations yet" : "Waiting for official NAVs",
                       message: pending.isEmpty
                           ? "After each market close, FundScope saves its final estimate for every fund it can estimate, then compares it with the official NAV once AMFI publishes it that evening. Keep FundScope open past 3:30 PM with Zerodha connected."
                           : "Saved \(pending.count) end-of-day estimate\(pending.count == 1 ? "" : "s") for \(pending.map(\.valuationDate).max().map(FinanceFormat.date) ?? "—"). They'll be compared once AMFI publishes the official NAVs, usually by late evening.")
        } else if let data = model.data {
            let estimable = data.funds.filter(\.isEstimable)
            let rows = data.reconciliations.filter { fundCode.isEmpty || $0.fundCode == fundCode }.sorted { $0.valuationDate > $1.valuationDate }
            let stats = AccuracyStats(rows)
            let names = Dictionary(uniqueKeysWithValues: data.funds.map { ($0.code, $0.name) })
            Page {
                PageHeader(title: "NAV Accuracy", subtitle: "Final estimate vs official NAV for the same day") {
                    Picker("Fund", selection: $fundCode) {
                        Text("All estimated funds").tag("")
                        ForEach(estimable) { Text($0.name).tag($0.code) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            } content: {
                if !stats.hasEnoughHistory {
                    InlineNotice(text: "Not enough history to judge accuracy yet: \(stats.count) reconciled days, at least \(AccuracyStats.minimumDaysForJudgement) needed.", tone: .warning)
                }
                MetricStrip {
                    MetricTile(label: "Reconciled days", value: Decimal(stats.count), kind: .count, compact: true)
                    MetricTile(label: "Mean abs. error", value: stats.meanAbsError, kind: .percent, missingReason: "No reconciliations yet", compact: true)
                    MetricTile(label: "Median abs. error", value: stats.medianAbsError, kind: .percent, missingReason: "No reconciliations yet", compact: true)
                    MetricTile(label: "Worst error", value: stats.worstError, kind: .percent, missingReason: "No reconciliations yet", compact: true)
                    MetricTile(label: "Within ±0.25%", value: stats.withinQuarterPercent, kind: .percent, missingReason: "No reconciliations yet", compact: true)
                }
                PageSection(title: "Daily error", caption: "Estimate minus official, % of official NAV") {
                    Chart {
                        RectangleMark(yStart: .value("Low", -0.25), yEnd: .value("High", 0.25))
                            .foregroundStyle(Palette.fill.opacity(0.3))
                        RuleMark(y: .value("Zero", 0)).foregroundStyle(Palette.borderSubtle)
                        ForEach(rows) { r in
                            BarMark(x: .value("Date", r.valuationDate, unit: .day), y: .value("Error", r.pctError.double))
                                .foregroundStyle(r.pctError >= 0 ? Palette.estimated : Palette.series[1])
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .trailing) { value in
                            AxisGridLine().foregroundStyle(Palette.borderSubtle)
                            AxisValueLabel { if let v = value.as(Double.self) { Text(FinanceFormat.percent(Decimal(v))) } }
                        }
                    }
                    .frame(height: Metrics.chartHeight)
                    Text("Shaded band: ±0.25%, shown for reference only.").textStyle(.caption)
                }
                PageSection(title: "Reconciliations", caption: "Saved estimates are never changed after the official NAV arrives") {
                    TableFrame(rows: rows.count, maxRows: 14) {
                        Table(rows) {
                            TableColumn("Date") { Text(FinanceFormat.date($0.valuationDate)).textStyle(.table) }
                            TableColumn("Fund") { Text(names[$0.fundCode] ?? $0.fundCode).textStyle(.table) }.width(min: 180, ideal: 240)
                            TableColumn("Estimated") { ValueText(value: $0.estimatedNAV, kind: .nav, color: Palette.estimated) }.alignment(.trailing)
                            TableColumn("Official") { ValueText(value: $0.officialNAV, kind: .nav) }.alignment(.trailing)
                            TableColumn("Error") { ValueText(value: $0.pctError, kind: .percent, signed: true) }.alignment(.trailing)
                            TableColumn("Coverage") { ValueText(value: $0.coverage, kind: .percent) }.alignment(.trailing)
                            TableColumn("Holdings as of") { Text(FinanceFormat.date($0.holdingsDate)).textStyle(.table) }
                            TableColumn("Model") { Text($0.modelVersion).textStyle(.table, color: Palette.textTertiary) }
                        }
                    }
                }
            }
        }
    }
}
