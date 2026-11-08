import FundScopeCore
import SwiftUI

/// The Nifty 50 index and its 50 stocks with live Kite prices, updating on their own while the page is open.
struct NiftyView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\Row.changeSort, order: .reverse)]
    @State private var query = ""

    nonisolated struct Row: Identifiable {
        let stock: NSESymbols.IndexStock
        let quote: Quote?
        var id: String { stock.symbol }
        var name: String { stock.name }
        var change: Decimal? { quote.map { $0.price - $0.previousClose } }
        var changePercent: Decimal? { quote.map { ($0.price / $0.previousClose - 1) * 100 } }
        var changeSort: Decimal { changePercent ?? .leastFiniteMagnitude }
        var priceSort: Decimal { quote?.price ?? 0 }
    }

    var body: some View {
        let quotes = model.niftyQuotes
        let rows = model.niftyStocks
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.symbol.localizedCaseInsensitiveContains(query) }
            .map { Row(stock: $0, quote: quotes[$0.symbol]) }
            .sorted(using: sortOrder)
        let index = quotes["NIFTY 50"]
        let moves = model.niftyStocks.compactMap { quotes[$0.symbol] }.map { $0.price - $0.previousClose }
        VStack(alignment: .leading, spacing: Space.m) {
            PageHeader(title: "Nifty 50", subtitle: subtitle) {
                MarketStatusBadge(status: model.marketStatus)
            }
            if model.kiteState != .connected {
                InlineNotice(text: "Live prices come from Kite: connect Zerodha in Settings → Zerodha.", tone: .warning)
            } else if let problem = model.niftyProblem {
                InlineNotice(text: "Couldn't update prices: \(problem). Showing the last prices.", tone: .warning)
            }
            MetricStrip {
                MetricTile(label: "Nifty 50", value: index?.price, kind: .points,
                           delta: index.map { ($0.price / $0.previousClose - 1) * 100 }, missingReason: "No live price yet")
                MetricTile(label: "Change today", value: index.map { $0.price - $0.previousClose }, kind: .points, colored: true,
                           missingReason: "No live price yet")
                MetricTile(label: "Advancing", value: moves.isEmpty ? nil : Decimal(moves.filter { $0 > 0 }.count), kind: .count)
                MetricTile(label: "Declining", value: moves.isEmpty ? nil : Decimal(moves.filter { $0 < 0 }.count), kind: .count)
            }
            if model.niftyStocks.isEmpty {
                LoadingState(label: "Downloading the Nifty 50 list from NSE…")
            } else {
                Table(rows, sortOrder: $sortOrder) {
                    TableColumn("Company", value: \.name) { Text($0.name).textStyle(.table) }
                        .width(min: 200, ideal: 260)
                    TableColumn("Symbol") { Text($0.stock.symbol).textStyle(.table, color: Palette.textSecondary) }
                        .width(min: 80, ideal: 110)
                    TableColumn("Industry") { Text($0.stock.industry).textStyle(.table, color: Palette.textSecondary) }
                        .width(min: 120, ideal: 170)
                    TableColumn("Price", value: \.priceSort) { row in
                        ValueText(value: row.quote?.price, kind: .currency, direction: row.change, missingReason: "No live price")
                    }
                    .width(min: 90, ideal: 110).alignment(.trailing)
                    TableColumn("Change") { row in
                        ValueText(value: row.change, kind: .currency, colored: true, missingReason: "No live price")
                    }
                    .width(min: 80, ideal: 100).alignment(.trailing)
                    TableColumn("% Change", value: \.changeSort) { row in
                        ValueText(value: row.changePercent, kind: .percent, colored: true, missingReason: "No live price")
                    }
                    .width(min: 80, ideal: 90).alignment(.trailing)
                }
                .hairlineBorder()
            }
            Text("Prices from Kite (NSE), compared with the previous close. The list of 50 stocks comes from NSE.")
                .textStyle(.caption)
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.l)
        .searchable(text: $query, prompt: "Company or symbol")
        .task { await model.streamNifty() }
    }

    private var subtitle: String {
        guard let at = model.niftyFetchedAt else { return "NSE · waiting for live prices" }
        return "NSE · updated \(FinanceFormat.timeWithSeconds(at))"
    }
}
