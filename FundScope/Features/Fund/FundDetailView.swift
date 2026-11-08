import Charts
import FundScopeCore
import SwiftUI

struct FundDetailView: View {
    let route: FundRoute
    @Environment(AppModel.self) private var model
    @State private var tab: FundRoute.Tab

    init(route: FundRoute) {
        self.route = route
        _tab = State(initialValue: route.tab)
    }

    var body: some View {
        if let data = model.data, let fund = model.fund(route.fundCode) {
            let estimate = Analytics.estimate(data, fund: fund)
            Page {
                PageHeader(title: fund.name, subtitle: "\(fund.amc) · \(fund.category) · \(fund.plan.rawValue.capitalized) plan") {
                    Picker("View", selection: $tab) {
                        ForEach(FundRoute.Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            } content: {
                switch tab {
                case .today: FundTodayView(fund: fund, data: data, estimate: estimate)
                case .history: FundHistoryView(fund: fund, data: data)
                case .holdings: FundHoldingsView(fund: fund, data: data)
                }
            }
            .navigationTitle(fund.name)
            .onAppear { model.inspect(fund.code) }
        } else {
            ErrorState(title: "Fund not found", message: "This fund is not in the current data set.")
        }
    }
}

// MARK: Today

private struct FundTodayView: View {
    let fund: FundInfo
    let data: Dataset
    let estimate: NAVEstimator.Estimate?
    @Environment(AppModel.self) private var model
    @State private var hoverTime: Date?
    @State private var showBenchmark = false

    var body: some View {
        let official = data.navHistory[fund.code]?.last
        let disclosure = Analytics.latestDisclosure(data, fund: fund.code)
        VStack(alignment: .leading, spacing: Space.xxl) {
            MetricStrip {
                MetricTile(label: "Official NAV", value: official?.nav, kind: .nav, source: .official(official?.date))
                MetricTile(label: "Est. live NAV", value: estimate?.estimatedNAV, kind: .nav, source: model.liveSource,
                           missingReason: reason)
                MetricTile(label: "Est. day return", value: estimate?.estimatedReturn, kind: .percent, colored: true, missingReason: reason)
                MetricTile(label: "Coverage", value: estimate?.coverage, kind: .percent,
                           source: disclosure.map { .holdings($0.disclosureDate) })
            }

            if let estimate {
                warnings(estimate, disclosure: disclosure)
                if estimate.estimatedNAV != nil {
                    chart(baseline: estimate.baselineNAV)
                    contributors(estimate)
                }
                holdingsTable(estimate)
                sectorContribution(estimate)
            } else {
                if disclosure == nil {
                    EmptyState(symbol: "doc.badge.ellipsis", title: "No holdings imported",
                               message: "Import this fund's monthly portfolio file to see what it owns.",
                               actionTitle: model.mode == .real ? "Import Fund Holdings" : nil) { model.showImportHoldings = true }
                } else {
                    EmptyState(symbol: "waveform.path.ecg", title: "No live prices yet",
                               message: "Holdings as of \(FinanceFormat.date(disclosure!.disclosureDate)) are imported; see the Holdings tab. Live estimates need stock prices from Kite Connect (Phase 4).")
                }
            }
        }
    }

    private var reason: String {
        if case .notEstimable(let r) = estimate?.status { return r }
        return "Not available"
    }

    @ViewBuilder private func warnings(_ e: NAVEstimator.Estimate, disclosure: Disclosure?) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            CoverageMeter(estimate: e)
            if case .notEstimable(let r) = e.status {
                InlineNotice(text: "No estimate for this fund: \(r).", tone: .warning)
            }
            if e.unpricedWeight > 0 {
                InlineNotice(text: "\(FinanceFormat.percent(e.unpricedWeight, signed: false)) of the fund has no fresh price. It is assumed to move with the priced stocks.", tone: .warning)
            }
            if let disclosure {
                InlineNotice(text: "Holdings as disclosed on \(FinanceFormat.date(disclosure.disclosureDate)). The fund may have traded since. Cash and debt are treated as flat. Model \(e.modelVersion).")
            }
        }
    }

    private func chart(baseline: Decimal) -> some View {
        let points = Analytics.intradayEstimate(data, fund: fund)
        let bench = data.benchmarkIntraday
        let benchBase = bench.first?.nav ?? 1
        let hovered = hoverTime.flatMap { t in points.last { $0.date <= t } }
        return PageSection(title: "Intraday estimate", caption: FinanceFormat.date(data.sessionDay)) {
            Toggle("Compare with \(data.benchmarkName)", isOn: $showBenchmark).toggleStyle(.checkbox)
        } content: {
            Chart {
                RuleMark(y: .value("Official", baseline.double))
                    .foregroundStyle(Palette.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Official NAV \(FinanceFormat.nav(baseline))").textStyle(.caption)
                    }
                ForEach(points, id: \.date) { p in
                    LineMark(x: .value("Time", p.date), y: .value("NAV", p.nav.double), series: .value("Series", "Estimate"))
                        .foregroundStyle(Palette.estimated)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                }
                if showBenchmark {
                    // Rebased so the index starts at the fund's official NAV.
                    ForEach(bench, id: \.date) { p in
                        LineMark(x: .value("Time", p.date), y: .value("NAV", (baseline * p.nav / benchBase).double), series: .value("Series", "Benchmark"))
                            .foregroundStyle(Palette.series[1])
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                if let hovered {
                    RuleMark(x: .value("Time", hovered.date))
                        .foregroundStyle(Palette.borderSubtle)
                        .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartTooltip(title: FinanceFormat.time(hovered.date), rows: [
                                ("Est. NAV", FinanceFormat.nav(hovered.nav), Palette.estimated),
                                ("Change", FinanceFormat.percent((hovered.nav / baseline - 1) * 100), nil),
                            ])
                        }
                }
            }
            .chartXSelection(value: $hoverTime)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(Palette.borderSubtle)
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour)) { _ in
                    AxisValueLabel(format: .dateTime.hour().minute())
                }
            }
            .frame(height: Metrics.chartHeight)
        }
    }

    private func contributors(_ e: NAVEstimator.Estimate) -> some View {
        let priced = e.contributions.filter { $0.contribution != nil }
        let up = priced.filter { $0.contribution! > 0 }.prefix(5)
        let down = priced.filter { $0.contribution! < 0 }.reversed().prefix(5)
        return HStack(alignment: .top, spacing: Space.xxl) {
            contributorList("Top positive contributors", Array(up))
            contributorList("Top negative contributors", Array(down))
        }
    }

    private func contributorList(_ title: String, _ items: [NAVEstimator.Contribution]) -> some View {
        PageSection(title: title) {
            if items.isEmpty {
                Text("None").textStyle(.secondary)
            } else {
                Grid(alignment: .leading, horizontalSpacing: Space.s, verticalSpacing: Space.xs) {
                    ForEach(items) { c in
                        GridRow {
                            Text(c.holding.security?.name ?? c.holding.rawName).textStyle(.table).lineLimit(1)
                            ValueText(value: c.quote?.change, kind: .percent, colored: true).gridColumnAlignment(.trailing)
                            ValueText(value: c.contribution, kind: .bps, colored: true).gridColumnAlignment(.trailing)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func holdingsTable(_ e: NAVEstimator.Estimate) -> some View {
        PageSection(title: "Holdings", caption: "Equity holdings with live prices") {
            TableFrame(rows: e.contributions.count, maxRows: 14) {
                ContributionTable(contributions: e.contributions, asOf: data.asOf)
            }
        }
    }

    private func sectorContribution(_ e: NAVEstimator.Estimate) -> some View {
        let bySector = Dictionary(grouping: e.contributions.filter { $0.contribution != nil }) { $0.holding.security?.sector ?? "Unmapped" }
            .map { ($0.key, $0.value.reduce(Decimal(0)) { $0 + $1.contribution! }) }
            .sorted { abs($0.1) > abs($1.1) }
        let maxAbs = bySector.map { abs($0.1) }.max() ?? 1
        return PageSection(title: "Sector contribution", caption: "Basis points of NAV change") {
            Grid(alignment: .leading, horizontalSpacing: Space.s, verticalSpacing: Space.xs) {
                ForEach(bySector, id: \.0) { sector, value in
                    GridRow {
                        Text(sector).textStyle(.table).frame(width: 160, alignment: .leading)
                        // Diverging bar around a centre line.
                        GeometryReader { geo in
                            let half = geo.size.width / 2
                            let w = max(1, half * (maxAbs == 0 ? 0 : abs(value) / maxAbs).cg)
                            Rectangle().fill(Palette.borderSubtle).frame(width: 1).offset(x: half)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(value >= 0 ? Palette.positive : Palette.negative)
                                .frame(width: w, height: 6)
                                .offset(x: value >= 0 ? half : half - w, y: 1)
                        }
                        .frame(height: 8)
                        ValueText(value: value, kind: .bps, colored: true).gridColumnAlignment(.trailing)
                    }
                }
            }
        }
    }
}

private struct ContributionTable: View {
    let contributions: [NAVEstimator.Contribution]
    let asOf: Date
    @State private var sortOrder = [KeyPathComparator(\Row.contributionSort, order: .reverse)]

    nonisolated struct Row: Identifiable {
        let c: NAVEstimator.Contribution
        var id: String { c.id }
        var name: String { c.holding.security?.name ?? c.holding.rawName }
        var weightSort: Decimal { c.holding.weight }
        var changeSort: Decimal { c.quote?.change ?? .leastFiniteMagnitude }
        var contributionSort: Decimal { c.contribution ?? .leastFiniteMagnitude }
    }

    var body: some View {
        Table(contributions.map(Row.init).sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Company", value: \Row.name) { row in
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.name).textStyle(.table)
                }
                .help(row.c.holding.security?.sector ?? "")
            }
            .width(min: 160, ideal: 200)
            TableColumn("Weight", value: \Row.weightSort) { ValueText(value: $0.c.holding.weight, kind: .percent) }
                .width(min: 60, ideal: 70).alignment(.trailing)
            TableColumn("Prev. close") { ValueText(value: $0.c.quote?.previousClose, kind: .nav, missingReason: "No quote") }
                .width(min: 80, ideal: 90).alignment(.trailing)
            TableColumn("Latest") { ValueText(value: $0.c.quote?.price, kind: .nav, missingReason: "No quote") }
                .width(min: 80, ideal: 90).alignment(.trailing)
            TableColumn("Change", value: \Row.changeSort) { ValueText(value: $0.c.quote?.change, kind: .percent, colored: true, missingReason: "No quote") }
                .width(min: 60, ideal: 70).alignment(.trailing)
            TableColumn("NAV contribution", value: \Row.contributionSort) { row in
                ValueText(value: row.c.contribution, kind: .bps, colored: true,
                          missingReason: row.c.isStale ? "Quote is stale, so this stock is counted as unpriced" : "No quote")
            }
            .width(min: 90, ideal: 110).alignment(.trailing)
            TableColumn("Quote") { row in
                if let q = row.c.quote {
                    Text(row.c.isStale ? "Stale · \(FinanceFormat.time(q.exchangeTime))" : FinanceFormat.time(q.exchangeTime))
                        .textStyle(.table, color: row.c.isStale ? Palette.warning : Palette.textSecondary)
                } else {
                    MissingValue(reason: "No quote")
                }
            }
            .width(min: 80, ideal: 90)
        }
    }
}

// MARK: NAV history

private struct FundHistoryView: View {
    let fund: FundInfo
    let data: Dataset
    @State private var range: TimeRange = .y1
    @State private var hoverDate: Date?

    var body: some View {
        let all = data.navHistory[fund.code] ?? []
        let end = all.last?.date ?? data.now
        let points = all.filter { $0.date >= range.start(from: end) }
        let hovered = hoverDate.flatMap { d in points.last { $0.date <= d } }
        if all.count < 2 {
            EmptyState(symbol: "chart.xyaxis.line", title: "No NAV history yet",
                       message: all.last.map { "Latest known NAV \(FinanceFormat.nav($0.nav)) on \(FinanceFormat.date($0.date)). Daily history arrives with the AMFI connection (Phase 3)." }
                           ?? "Daily NAV history arrives with the AMFI connection (Phase 3).")
        } else {
        VStack(alignment: .leading, spacing: Space.xxl) {
            MetricStrip {
                ForEach([TimeRange.m1, .m6, .y1, .y3], id: \.self) { r in
                    MetricTile(label: "\(r.rawValue) return", value: trailingReturn(all, r), kind: .percent, colored: true,
                               missingReason: "Not enough NAV history")
                }
            }
            PageSection(title: "Official NAV", caption: "AMFI, end of day") {
                RangePicker(range: $range, options: [.m1, .m3, .m6, .y1, .y3, .all])
            } content: {
                Chart {
                    ForEach(points, id: \.date) { p in
                        LineMark(x: .value("Date", p.date), y: .value("NAV", p.nav.double))
                            .foregroundStyle(Palette.series[0])
                    }
                    if let hovered {
                        RuleMark(x: .value("Date", hovered.date))
                            .foregroundStyle(Palette.borderSubtle)
                            .annotation(position: .top, spacing: 0, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                ChartTooltip(title: FinanceFormat.date(hovered.date), rows: [("NAV", FinanceFormat.nav(hovered.nav), Palette.series[0])])
                            }
                    }
                }
                .chartXSelection(value: $hoverDate)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine().foregroundStyle(Palette.borderSubtle); AxisValueLabel() } }
                .frame(height: Metrics.chartHeight)
            }
        }
        }
    }

    private func trailingReturn(_ points: [NAVPoint], _ r: TimeRange) -> Decimal? {
        points.last.flatMap { Analytics.trailingReturn(points, from: r.start(from: $0.date)) }
    }
}

// MARK: Holdings

private struct FundHoldingsView: View {
    let fund: FundInfo
    let data: Dataset
    @Environment(AppModel.self) private var model

    var body: some View {
        if let d = Analytics.latestDisclosure(data, fund: fund.code) {
            let sectors = DisclosureDiff.sectorWeights(d).map { BarList.Item(id: $0.key, label: $0.key, share: $0.value) }.sorted { $0.share > $1.share }
            VStack(alignment: .leading, spacing: Space.xxl) {
                PageSection(title: "Disclosed portfolio", caption: "As of \(FinanceFormat.date(d.disclosureDate)) · \(d.holdings.count) holdings") {
                    TableFrame(rows: d.holdings.count, maxRows: 16) {
                        Table(d.holdings) {
                            TableColumn("Holding") { Text($0.security?.name ?? $0.rawName).textStyle(.table) }.width(min: 200, ideal: 240)
                            TableColumn("Sector") { Text($0.security?.sector ?? "—").textStyle(.table, color: Palette.textSecondary) }
                            TableColumn("Asset type") { Text($0.assetType.label).textStyle(.table, color: Palette.textSecondary) }
                            TableColumn("Weight") { ValueText(value: $0.weight, kind: .percent) }.alignment(.trailing)
                            TableColumn("Quantity") { ValueText(value: $0.quantity, kind: .units, missingReason: "Not published in the disclosure") }.alignment(.trailing)
                        }
                    }
                }
                HStack(alignment: .top, spacing: Space.xxl) {
                    PageSection(title: "Sector mix") { BarList(items: sectors, maxItems: 10) }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PageSection(title: "Disclosure history") {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            ForEach((data.disclosures[fund.code] ?? []).reversed()) { item in
                                HStack {
                                    Text(FinanceFormat.month(item.disclosureDate)).textStyle(.table)
                                    Spacer()
                                    Text("\(item.holdings.count) holdings").textStyle(.caption)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else {
            EmptyState(symbol: "doc.badge.plus", title: "No holdings imported",
                       message: "Download this fund's monthly portfolio file from the fund house's website and import it.",
                       actionTitle: "Import Fund Holdings") { model.showImportHoldings = true }
        }
    }
}
