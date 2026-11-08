import FundScopeCore
import SwiftUI

/// Month-to-month comparison of a fund's disclosed portfolio.
struct PortfolioChangesView: View {
    @Environment(AppModel.self) private var model
    @State private var fundCode = ""
    @State private var oldIndex = 0
    @State private var newIndex = 1

    var body: some View {
        if let data = model.data {
            let funds = data.funds.filter { (data.disclosures[$0.code]?.count ?? 0) >= 2 }
            let code = fundCode.isEmpty ? (funds.first?.code ?? "") : fundCode
            let list = data.disclosures[code] ?? []
            Page {
                PageHeader(title: "Holdings Changes", subtitle: "Stocks the fund manager bought and sold between disclosures") {
                    FundPicker(funds: funds, selection: Binding(get: { code }, set: { fundCode = $0; oldIndex = 0; newIndex = 1 }))
                }
            } content: {
                if list.count < 2 {
                    EmptyState(symbol: "doc.on.doc", title: "Two months needed",
                               message: "Import at least two monthly portfolio files for a fund to see what its manager bought and sold.",
                               actionTitle: model.mode == .real ? "Import Fund Holdings" : nil) { model.showImportHoldings = true }
                } else {
                    let older = list[min(oldIndex, list.count - 1)]
                    let newer = list[min(newIndex, list.count - 1)]
                    let changes = DisclosureDiff.compare(old: older, new: newer)
                    HStack(spacing: Space.m) {
                        monthPicker("From", list: list, selection: $oldIndex)
                        Image(systemName: "arrow.right").foregroundStyle(Palette.textTertiary)
                        monthPicker("To", list: list, selection: $newIndex)
                        Spacer()
                    }
                    MetricStrip {
                        ForEach([DisclosureDiff.Kind.new, .exited, .increased, .decreased], id: \.self) { kind in
                            MetricTile(label: label(kind), value: Decimal(changes.filter { $0.kind == kind }.count), kind: .count, compact: true)
                        }
                        MetricTile(label: "Top 10 weight", value: top10(newer), kind: .percent,
                                   delta: top10(newer) - top10(older), deltaKind: .percent, compact: true)
                    }
                    ForEach([DisclosureDiff.Kind.new, .exited, .increased, .decreased], id: \.self) { kind in
                        let items = changes.filter { $0.kind == kind }
                        if !items.isEmpty {
                            PageSection(title: label(kind), caption: "\(items.count)") {
                                ChangeTable(changes: items)
                            }
                        }
                    }
                    sectorChanges(older, newer)
                }
            }
        }
    }

    private func monthPicker(_ title: String, list: [Disclosure], selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, d in
                Text(FinanceFormat.date(d.disclosureDate)).tag(i)
            }
        }
        .fixedSize()
    }

    private func label(_ kind: DisclosureDiff.Kind) -> String {
        switch kind {
        case .new: "New holdings"
        case .exited: "Exited"
        case .increased: "Increased"
        case .decreased: "Decreased"
        case .unchanged: "Unchanged"
        }
    }

    private func top10(_ d: Disclosure) -> Decimal {
        d.holdings.filter { $0.assetType == .equity }.map(\.weight).sorted(by: >).prefix(10).reduce(0, +)
    }

    private func sectorChanges(_ older: Disclosure, _ newer: Disclosure) -> some View {
        let a = DisclosureDiff.sectorWeights(older), b = DisclosureDiff.sectorWeights(newer)
        let rows = Set(a.keys).union(b.keys).map { ($0, b[$0] ?? 0, (b[$0] ?? 0) - (a[$0] ?? 0)) }.sorted { abs($0.2) > abs($1.2) }
        return PageSection(title: "Sector allocation change") {
            Grid(alignment: .leading, horizontalSpacing: Space.l, verticalSpacing: Space.xs) {
                GridRow {
                    Text("Sector").textStyle(.cardTitle)
                    Text("Now").textStyle(.cardTitle).gridColumnAlignment(.trailing)
                    Text("Change").textStyle(.cardTitle).gridColumnAlignment(.trailing)
                }
                ForEach(rows, id: \.0) { sector, now, change in
                    GridRow {
                        Text(sector).textStyle(.table)
                        ValueText(value: now, kind: .percent)
                        ValueText(value: change, kind: .percent, colored: true)
                    }
                }
            }
        }
    }
}

private struct ChangeTable: View {
    let changes: [DisclosureDiff.Change]

    var body: some View {
        TableFrame(rows: changes.count, maxRows: 10) {
            Table(changes) {
                TableColumn("Holding") { Text($0.name).textStyle(.table) }.width(min: 180, ideal: 220)
                TableColumn("Sector") { Text($0.sector ?? "—").textStyle(.table, color: Palette.textSecondary) }
                TableColumn("Weight before") { ValueText(value: $0.oldWeight, kind: .percent, missingReason: "Not held") }.alignment(.trailing)
                TableColumn("Weight after") { ValueText(value: $0.newWeight, kind: .percent, missingReason: "Not held") }.alignment(.trailing)
                TableColumn("Weight change") { ValueText(value: $0.weightChange, kind: .percent, colored: true) }.alignment(.trailing)
                TableColumn("Quantity change") { c in
                    // Quantity is the confirmed trade; weight can also move with price.
                    ValueText(value: c.oldQuantity.flatMap { o in c.newQuantity.flatMap { o > 0 ? ($0 / o - 1) * 100 : nil } },
                              kind: .percent, colored: true, missingReason: "Quantity not published in both disclosures")
                }
                .alignment(.trailing)
                TableColumn("Basis") { c in
                    if c.possibleCorporateAction {
                        Pill(text: "Possible split/bonus", tint: Palette.warning)
                    } else if c.isQuantityConfirmed {
                        Pill(text: "Quantity change", tint: Palette.textSecondary)
                    } else if c.kind == .increased || c.kind == .decreased {
                        Pill(text: "Weight only", tint: Palette.textTertiary)
                            .help("Only weights were disclosed. The change may come from price movement, not trading.")
                    }
                }
                .width(min: 120, ideal: 140)
            }
        }
    }
}
