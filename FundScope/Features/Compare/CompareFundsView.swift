import Charts
import FundScopeCore
import SwiftUI

struct CompareFundsView: View {
    @Environment(AppModel.self) private var model
    @State private var selected: Set<String> = []
    @State private var range: TimeRange = .y1
    @State private var showBenchmark = true
    @State private var hoverDate: Date?

    var body: some View {
        if let data = model.data {
            let funds = data.funds.filter { selected.contains($0.code) }
            Page {
                PageHeader(title: "Compare Funds", subtitle: "Rebased to 100 at the start of the range") {
                    FundMultiPicker(funds: data.funds, selection: $selected)
                }
            } content: {
                if funds.contains(where: { (data.navHistory[$0.code]?.count ?? 0) < 2 }) && !funds.isEmpty && funds.count >= 2 {
                    EmptyState(symbol: "chart.line.uptrend.xyaxis", title: "No NAV history to compare",
                               message: "Comparisons need daily official NAVs, which arrive with the AMFI connection (Phase 3).")
                        .frame(height: 300)
                } else if funds.count < 2 {
                    EmptyState(symbol: "chart.line.uptrend.xyaxis", title: "Pick at least two funds",
                               message: "Choose up to five funds to compare performance, overlap and allocation.")
                        .frame(height: 300)
                } else {
                    performance(data, funds)
                    returnsTable(data, funds)
                    PageSection(title: "Holdings overlap", caption: "Sum of the smaller weight for each company both funds hold") {
                        OverlapMatrix(data: data, funds: funds)
                    }
                }
            }
            .onAppear {
                if selected.isEmpty { selected = Set((data.isDemo ? data.funds.filter(\.isEstimable) : data.funds).prefix(3).map(\.code)) }
            }
        }
    }

    private struct Series: Identifiable {
        let id: String
        let name: String
        let color: Color
        let points: [NAVPoint]
    }

    private func series(_ data: Dataset, _ funds: [FundInfo]) -> [Series] {
        let end = data.navHistory.values.first?.last?.date ?? data.now
        let start = range.start(from: end)
        func rebased(_ pts: [NAVPoint]) -> [NAVPoint] {
            let window = pts.filter { $0.date >= start }
            guard let base = window.first?.nav, base > 0 else { return [] }
            return window.map { NAVPoint(date: $0.date, nav: $0.nav / base * 100) }
        }
        var result = funds.enumerated().map { i, f in
            Series(id: f.code, name: f.name, color: Palette.series[i % Palette.series.count], points: rebased(data.navHistory[f.code] ?? []))
        }
        if showBenchmark, !data.benchmarkHistory.isEmpty {
            result.append(Series(id: "benchmark", name: "\(data.benchmarkName) (price index)", color: Palette.textSecondary, points: rebased(data.benchmarkHistory)))
        }
        return result
    }

    private func performance(_ data: Dataset, _ funds: [FundInfo]) -> some View {
        let all = series(data, funds)
        return PageSection(title: "Performance") {
            HStack(spacing: Space.m) {
                if !data.benchmarkHistory.isEmpty {
                    Toggle("Benchmark", isOn: $showBenchmark).toggleStyle(.checkbox)
                } else {
                    Text("Benchmark needs Kite Connect").textStyle(.caption)
                }
                RangePicker(range: $range, options: [.m3, .m6, .y1, .y3, .all])
            }
        } content: {
            Chart {
                ForEach(all) { s in
                    ForEach(s.points, id: \.date) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Value", p.nav.double), series: .value("Fund", s.id))
                            .foregroundStyle(s.color)
                            .lineStyle(StrokeStyle(lineWidth: s.id == "benchmark" ? 1 : 1.5, dash: s.id == "benchmark" ? [3, 3] : []))
                    }
                }
                if let hoverDate {
                    RuleMark(x: .value("Date", hoverDate))
                        .foregroundStyle(Palette.borderSubtle)
                        .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartTooltip(title: FinanceFormat.date(hoverDate), rows: all.compactMap { s in
                                s.points.last { $0.date <= hoverDate }.map { (s.name, FinanceFormat.plain($0.nav, digits: 1), s.color) }
                            })
                        }
                }
            }
            .chartXSelection(value: $hoverDate)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine().foregroundStyle(Palette.borderSubtle); AxisValueLabel() } }
            .frame(height: Metrics.chartHeight)
            HStack(spacing: Space.m) {
                ForEach(all) { s in
                    HStack(spacing: Space.xxs) {
                        Circle().fill(s.color).frame(width: 6, height: 6)
                        Text(s.name).textStyle(.caption)
                    }
                }
            }
            if showBenchmark, !data.benchmarkHistory.isEmpty {
                Text("Fund NAVs include reinvested dividends; the price index does not.").textStyle(.caption)
            }
        }
    }

    private func returnsTable(_ data: Dataset, _ funds: [FundInfo]) -> some View {
        let periods: [TimeRange] = [.m1, .m3, .m6, .y1, .y3]
        func ret(_ pts: [NAVPoint], _ r: TimeRange) -> Decimal? {
            pts.last.flatMap { Analytics.trailingReturn(pts, from: r.start(from: $0.date)) }
        }
        let benchmark: [(String, [NAVPoint])] = data.benchmarkHistory.isEmpty ? [] : [(data.benchmarkName, data.benchmarkHistory)]
        let rows: [(String, [NAVPoint])] = funds.map { ($0.name, data.navHistory[$0.code] ?? []) } + benchmark
        return PageSection(title: "Trailing returns", caption: "Absolute, not annualised") {
            Grid(alignment: .trailing, horizontalSpacing: Space.l, verticalSpacing: Space.xs) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(periods) { Text($0.rawValue).textStyle(.cardTitle) }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(rows, id: \.0) { name, pts in
                    GridRow {
                        Text(name).textStyle(.table).lineLimit(1)
                        ForEach(periods) { ValueText(value: ret(pts, $0), kind: .percent, colored: true, missingReason: "Not enough history") }
                    }
                }
            }
        }
    }
}

/// Pairwise holdings overlap between funds.
struct OverlapMatrix: View {
    let data: Dataset
    let funds: [FundInfo]

    var body: some View {
        Grid(alignment: .center, horizontalSpacing: Space.xxs, verticalSpacing: Space.xxs) {
            GridRow {
                Text("")
                ForEach(funds) { Text(short($0.name)).textStyle(.caption).frame(width: 90).lineLimit(2).multilineTextAlignment(.center) }
            }
            ForEach(funds) { a in
                GridRow {
                    Text(short(a.name)).textStyle(.table).frame(width: 160, alignment: .leading).lineLimit(1)
                    ForEach(funds) { b in
                        cell(a, b)
                    }
                }
            }
        }
    }

    private func cell(_ a: FundInfo, _ b: FundInfo) -> some View {
        let da = Analytics.latestDisclosure(data, fund: a.code)
        let db = Analytics.latestDisclosure(data, fund: b.code)
        let value: Decimal? = a == b ? nil : (da.flatMap { x in db.map { LookThrough.overlap(x, $0) } })
        return ZStack {
            RoundedRectangle(cornerRadius: Radius.small)
                .fill(Palette.series[0].opacity(a == b ? 0.03 : 0.05 + 0.5 * ((value ?? 0) / 100).double))
            if a == b {
                Text("—").textStyle(.caption)
            } else {
                ValueText(value: value, kind: .percent, missingReason: "Disclosure missing")
            }
        }
        .frame(width: 90, height: 28)
    }

    private func short(_ name: String) -> String { name.replacingOccurrences(of: " Fund", with: "") }
}
