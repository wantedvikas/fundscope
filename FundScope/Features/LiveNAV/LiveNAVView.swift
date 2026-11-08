import FundScopeCore
import SwiftUI

struct LiveNAVView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\Row.changeSort, order: .reverse)]
    @State private var selection: String?
    @State private var query = ""

    nonisolated struct Row: Identifiable {
        let fund: FundInfo
        let official: NAVPoint?
        let estimate: NAVEstimator.Estimate?
        let holdingsDate: Date?
        var id: String { fund.code }
        var name: String { fund.name }
        var changeSort: Decimal { estimate?.estimatedReturn ?? .leastFiniteMagnitude }
        var coverageSort: Decimal { estimate?.coverage ?? 0 }
    }

    var body: some View {
        if let data = model.data {
            let rows = data.funds
                .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
                .map { Row(fund: $0, official: data.navHistory[$0.code]?.last,
                           estimate: Analytics.estimate(data, fund: $0),
                           holdingsDate: Analytics.latestDisclosure(data, fund: $0.code)?.disclosureDate) }
                .sorted(using: sortOrder)
            VStack(alignment: .leading, spacing: Space.m) {
                PageHeader(title: "Live NAV", subtitle: "\(data.funds.count) tracked funds · \(model.liveSource.text)") {
                    MarketStatusBadge(status: model.marketStatus)
                }
                if !data.isDemo {
                    InlineNotice(text: model.quotes.isEmpty
                                 ? "Live estimates need each fund's monthly holdings (⇧⌘I) and live stock prices: connect Zerodha in Settings → Zerodha."
                                 : "Estimated from imported holdings and Kite prices at \(model.quotesFetchedAt.map(FinanceFormat.time) ?? "—"). Official NAVs come from AMFI.")
                } else if !data.sessionIsLive {
                    InlineNotice(text: "The market is closed. Estimates show the last session (\(FinanceFormat.date(data.sessionDay))) until the official NAV replaces them.")
                }
                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Fund", value: \.name) { Text($0.name).textStyle(.table) }
                        .width(min: 200, ideal: 240)
                    TableColumn("Official NAV") { row in
                        VStack(alignment: .trailing, spacing: 0) {
                            ValueText(value: row.official?.nav, kind: .nav)
                        }
                        .help(row.official.map { "Official NAV for \(FinanceFormat.date($0.date))" } ?? "")
                    }
                    .width(min: 90, ideal: 100).alignment(.trailing)
                    TableColumn("Est. NAV") { row in
                        ValueText(value: row.estimate?.estimatedNAV, kind: .nav, color: Palette.estimated, missingReason: reason(row.estimate))
                    }
                    .width(min: 90, ideal: 100).alignment(.trailing)
                    TableColumn("Est. change", value: \.changeSort) { row in
                        ValueText(value: row.estimate?.estimatedReturn, kind: .percent, colored: true, missingReason: reason(row.estimate))
                    }
                    .width(min: 80, ideal: 90).alignment(.trailing)
                    TableColumn("Coverage", value: \.coverageSort) { row in
                        if let e = row.estimate {
                            HStack(spacing: Space.xs) {
                                CoverageMeter(estimate: e, showLegend: false).frame(width: 48)
                                ValueText(value: e.coverage, kind: .percent, digits: 0)
                            }
                        }
                    }
                    .width(min: 100, ideal: 110)
                    TableColumn("Holdings as of") { row in
                        Text(row.holdingsDate.map(FinanceFormat.date) ?? "—").textStyle(.table)
                    }
                    .width(min: 90, ideal: 100)
                    TableColumn("Status") { row in
                        if let e = row.estimate { Pill.estimateStatus(e.status).help(reason(e)) }
                    }
                    .width(min: 100, ideal: 110)
                }
                .hairlineBorder()
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first { Button("Open Fund") { model.open(id) } }
                } primaryAction: { ids in
                    if let id = ids.first { model.open(id) }
                }
                .onChange(of: selection) { _, id in model.inspect(id) }
                Text("Estimates use each fund's last disclosed holdings and live prices of the stocks in it. They are not official NAVs.")
                    .textStyle(.caption)
            }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.l)
            .searchable(text: $query, prompt: "Search funds")
        }
    }

    private func reason(_ e: NAVEstimator.Estimate?) -> String {
        if case .notEstimable(let r) = e?.status { return r }
        if case .lowCoverage = e?.status { return "Less than 90% of the fund has live prices" }
        return "Estimated from disclosed holdings"
    }
}
