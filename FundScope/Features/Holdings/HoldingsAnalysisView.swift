import FundScopeCore
import SwiftUI

/// Look-through exposure across all funds in the portfolio.
struct HoldingsAnalysisView: View {
    enum Segment: String, CaseIterable { case companies = "Companies", sectors = "Sectors", marketCap = "Market cap", overlap = "Overlap" }

    @Environment(AppModel.self) private var model
    @State private var segment = Segment.companies

    var body: some View {
        if let data = model.data, data.disclosures.isEmpty {
            EmptyState(symbol: "circle.hexagongrid", title: "No fund holdings yet",
                       message: "See which companies and sectors your funds own together. Import each fund's monthly portfolio file from its fund house.",
                       actionTitle: "Import Fund Holdings") { model.showImportHoldings = true }
        } else if let data = model.data {
            let companies = Analytics.exposures(data) { ($0.isin, $0.name) }
            let equities = companies.filter { !$0.id.hasPrefix("__") }
            let unmapped = companies.first { $0.id == LookThrough.unmappedKey }?.share
            let nonEquity = companies.first { $0.id == LookThrough.nonEquityKey }?.share
            Page {
                PageHeader(title: "Holdings Analysis", subtitle: "Companies held through your funds · each fund counts equally") {
                    Picker("View", selection: $segment) {
                        ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            } content: {
                MetricStrip {
                    MetricTile(label: "Unique companies", value: Decimal(equities.count), kind: .count, compact: true)
                    MetricTile(label: "Top 10 share", value: equities.prefix(10).reduce(0) { $0 + $1.share }, kind: .percent, compact: true)
                    MetricTile(label: "Largest company", value: equities.first?.share, kind: .percent, compact: true)
                    MetricTile(label: "Unmapped", value: unmapped ?? 0, kind: .percent, compact: true)
                    MetricTile(label: "Cash, debt & other", value: nonEquity ?? 0, kind: .percent, compact: true)
                }
                switch segment {
                case .companies:
                    PageSection(title: "Combined company exposure", caption: "Average of each company's weight across your funds") {
                        TableFrame(rows: companies.count, maxRows: 18) { ExposureTable(rows: companies, data: data) }
                    }
                case .sectors:
                    PageSection(title: "Sector exposure") {
                        BarList(items: items(Analytics.exposures(data) { ($0.sector, $0.sector) }), maxItems: 16)
                    }
                case .marketCap:
                    PageSection(title: "Market-cap exposure") {
                        BarList(items: items(Analytics.exposures(data) { ($0.marketCap?.rawValue ?? "unknown", $0.marketCap?.label ?? "Unclassified") }))
                    }
                case .overlap:
                    PageSection(title: "Fund overlap", caption: "Funds in your watchlist") {
                        OverlapMatrix(data: data, funds: data.funds.filter { Analytics.latestDisclosure(data, fund: $0.code) != nil })
                    }
                }
                Text("Based on each fund's latest disclosure. Unmapped and non-equity holdings are shown separately and are never assigned to a company.")
                    .textStyle(.caption)
            }
        }
    }

    private func items(_ rows: [LookThrough.Exposure]) -> [BarList.Item] {
        rows.map { BarList.Item(id: $0.id, label: $0.name, share: $0.share, muted: $0.id.hasPrefix("__")) }
    }
}

private struct ExposureTable: View {
    let rows: [LookThrough.Exposure]
    let data: Dataset
    @State private var sortOrder = [KeyPathComparator(\LookThrough.Exposure.share, order: .reverse)]

    var body: some View {
        let names = Dictionary(uniqueKeysWithValues: data.funds.map { ($0.code, $0.name) })
        let sectors = Dictionary(uniqueKeysWithValues: data.securities.map { ($0.isin, $0.sector) })
        Table(rows.sorted(using: sortOrder), sortOrder: $sortOrder) {
            TableColumn("Company", value: \.name) { row in
                Text(row.name).textStyle(.table, color: row.id.hasPrefix("__") ? Palette.textSecondary : Palette.textPrimary)
            }
            .width(min: 180, ideal: 220)
            TableColumn("Sector") { Text(sectors[$0.id] ?? "—").textStyle(.table, color: Palette.textSecondary) }
            TableColumn("Avg. weight", value: \.share) { ValueText(value: $0.share, kind: .percent) }.alignment(.trailing)
            TableColumn("Held via") { row in
                Text(row.fundCodes.count == 1 ? (names[row.fundCodes[0]] ?? "") : "\(row.fundCodes.count) funds")
                    .textStyle(.table, color: Palette.textSecondary)
                    .help(row.fundCodes.compactMap { names[$0] }.joined(separator: "\n"))
            }
        }
    }
}
