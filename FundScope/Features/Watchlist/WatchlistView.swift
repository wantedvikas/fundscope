import FundScopeCore
import SwiftUI

/// The funds you follow: official NAV, latest change, live estimate, and what they hold together.
struct WatchlistView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let data = model.data {
            let funds = model.watched
            Page {
                PageHeader(title: "Watchlist", subtitle: subtitle(data)) {
                    HStack(spacing: Space.s) {
                        MarketStatusBadge(status: model.marketStatus)
                        if !data.isDemo {
                            Button("Import Holdings", systemImage: "tray.and.arrow.down") { model.showImportHoldings = true }
                        }
                        Button("Add Funds", systemImage: "plus") { model.showAddFunds = true }
                            .disabled(data.isDemo && model.container == nil)
                    }
                }
            } content: {
                MetricStrip {
                    MetricTile(label: "Funds", value: Decimal(funds.count), kind: .count)
                    MetricTile(label: "Avg. official change", value: Analytics.averageOfficialChange(funds), kind: .percent, colored: true,
                               source: Analytics.averageOfficialChange(funds) == nil ? nil : funds.compactMap(\.official?.date).max().map { .official($0) },
                               missingReason: "Needs two days of official NAVs")
                    MetricTile(label: "Avg. est. change", value: Analytics.averageEstimatedChange(funds), kind: .percent, colored: true,
                               source: Analytics.averageEstimatedChange(funds) == nil ? nil : model.liveSource,
                               missingReason: "Live estimates need fund holdings and live prices")
                    MetricTile(label: "Live estimates", value: Decimal(funds.filter { $0.estimate?.estimatedNAV != nil }.count), kind: .count)
                }
                .help("Averages count every fund equally. FundScope doesn't know or store what you invested.")
                PageSection(title: "Funds", caption: "\(funds.count) funds") {
                    TableFrame(rows: funds.count, maxRows: 16) { WatchlistTable(funds: funds) }
                }
                if let error = model.historyError {
                    InlineNotice(text: error, tone: .warning)
                }
                composition(data, funds)
            }
        }
    }

    private func subtitle(_ data: Dataset) -> String {
        if data.isDemo { return "Demo funds · \(model.liveSource.text)" }
        if let p = model.historyProgress { return "Downloading NAV history from AMFI… \(p.done) of \(p.total)" }
        return model.amfiFetchedAt.map { "Official NAVs from AMFI · updated \(FinanceFormat.shortDate($0)), \(FinanceFormat.time($0))" }
            ?? "Waiting for AMFI's NAV file"
    }

    private func composition(_ data: Dataset, _ funds: [WatchedFund]) -> some View {
        func counts(_ key: (FundInfo) -> String) -> [BarList.Item] {
            Dictionary(grouping: funds, by: { key($0.fund) }).map { k, v in
                BarList.Item(id: k, label: k, share: Decimal(v.count) / Decimal(max(funds.count, 1)) * 100)
            }
            .sorted { $0.share > $1.share }
        }
        func exposure(_ key: @escaping (SecurityInfo) -> (id: String, name: String)) -> [BarList.Item] {
            Analytics.exposures(data, key: key).map {
                BarList.Item(id: $0.id, label: $0.name, share: $0.share, muted: $0.id.hasPrefix("__"))
            }
        }
        return PageSection(title: "Composition", caption: "Each fund counts equally") {
            Grid(alignment: .topLeading, horizontalSpacing: Space.xxl, verticalSpacing: Space.xl) {
                GridRow {
                    block("Fund category", counts { $0.category })
                    block("Fund house", counts { $0.amc })
                }
                GridRow {
                    block("Sector (look-through)", exposure { ($0.sector, $0.sector) })
                    block("Market cap (look-through)", exposure { ($0.marketCap?.rawValue ?? "unknown", $0.marketCap?.label ?? "Unclassified") })
                }
                GridRow {
                    block("Top companies across your funds", exposure { ($0.isin, $0.name) }.filter { !$0.muted })
                        .gridCellColumns(2)
                }
            }
        }
    }

    private func block(_ title: String, _ items: [BarList.Item]) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).textStyle(.cardTitle)
            if items.isEmpty {
                Text("Import fund holdings (⇧⌘I) to see this.").textStyle(.caption)
            } else {
                BarList(items: items, maxItems: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WatchlistTable: View {
    let funds: [WatchedFund]
    @Environment(AppModel.self) private var model
    @State private var selection: String?
    @State private var sortOrder = [KeyPathComparator(\Row.name)]

    nonisolated struct Row: Identifiable {
        let w: WatchedFund
        var id: String { w.id }
        var name: String { w.fund.name }
        var category: String { w.fund.category }
        // Unknown values sort last instead of pretending to be zero.
        var changeSort: Decimal { w.officialChange ?? .leastFiniteMagnitude }
        var estSort: Decimal { w.estimate?.estimatedReturn ?? .leastFiniteMagnitude }
        let month: Decimal?
        let year: Decimal?
        var monthSort: Decimal { month ?? .leastFiniteMagnitude }
        var yearSort: Decimal { year ?? .leastFiniteMagnitude }
    }

    private func row(_ w: WatchedFund) -> Row {
        let history = model.data?.navHistory[w.fund.code] ?? []
        let end = history.last?.date ?? .now
        return Row(w: w, month: Analytics.trailingReturn(history, from: TimeRange.m1.start(from: end)),
                   year: Analytics.trailingReturn(history, from: TimeRange.y1.start(from: end)))
    }

    var body: some View {
        Table(funds.map(row).sorted(using: sortOrder), selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Fund", value: \Row.name) { row in
                Text(row.name).textStyle(.table).help(row.w.fund.amc)
            }
            .width(min: 160, ideal: 220)
            TableColumn("Category", value: \Row.category) { Text($0.category).textStyle(.table, color: Palette.textSecondary) }
                .width(min: 80, ideal: 100)
            TableColumn("Official NAV") { row in
                ValueText(value: row.w.official?.nav, kind: .nav, missingReason: "AMFI hasn't published a NAV yet")
                    .help(row.w.official.map { "Official NAV for \(FinanceFormat.date($0.date))" } ?? "")
            }
            .width(min: 80, ideal: 90).alignment(.trailing)
            TableColumn("1D", value: \Row.changeSort) {
                ValueText(value: $0.w.officialChange, kind: .percent, colored: true, missingReason: "Needs two days of official NAVs")
            }
            .width(min: 60, ideal: 70).alignment(.trailing)
            TableColumn("1M", value: \Row.monthSort) { ValueText(value: $0.month, kind: .percent, colored: true, missingReason: "Not enough NAV history yet") }
                .width(min: 55, ideal: 65).alignment(.trailing)
            TableColumn("1Y", value: \Row.yearSort) { ValueText(value: $0.year, kind: .percent, colored: true, missingReason: "Not enough NAV history yet") }
                .width(min: 55, ideal: 65).alignment(.trailing)
            TableColumn("Est. change", value: \Row.estSort) { row in
                ValueText(value: row.w.estimate?.estimatedReturn, kind: .percent, colored: true, missingReason: reason(row.w))
            }
            .width(min: 80, ideal: 90).alignment(.trailing)
            TableColumn("Live estimate") { row in
                if let e = row.w.estimate { Pill.estimateStatus(e.status).help(reason(row.w)) }
                else { Text(!row.w.fund.isEstimable ? "Not estimable" : row.w.holdingsDate == nil ? "Needs holdings" : "Needs prices").textStyle(.caption).help(reason(row.w)) }
            }
            .width(min: 95, ideal: 105)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first {
                Button("Open Fund") { model.open(id) }
                Button("Show Holdings") { model.open(id, tab: .holdings) }
                if model.mode == .real {
                    Divider()
                    Button("Remove from Watchlist") { model.remove(id) }
                }
            }
        } primaryAction: { ids in
            if let id = ids.first { model.open(id) }
        }
        .onDeleteCommand { if let selection { model.remove(selection) } }
        .onChange(of: selection) { _, id in model.inspect(id) }
    }

    private func reason(_ w: WatchedFund) -> String {
        if case .notEstimable(let r) = w.estimate?.status { return r }
        if !w.fund.isEstimable { return "\(w.fund.category) funds hold debt, derivatives or other assets the model can't price live" }
        if w.estimate == nil, w.holdingsDate == nil { return "Import this fund's monthly holdings (⇧⌘I); live estimates also need stock prices" }
        if w.estimate == nil { return "Holdings imported. Live estimates need stock prices from Kite Connect (Phase 4)" }
        return "Estimated from disclosed holdings"
    }
}
