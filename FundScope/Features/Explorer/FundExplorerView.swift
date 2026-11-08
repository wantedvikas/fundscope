import FundScopeCore
import SwiftUI

/// Browse schemes: the full AMFI list for your watchlist, or the demo set in demo mode.
struct FundExplorerView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var category = ""
    @State private var directOnly = true
    @State private var selection: String?

    private static let displayLimit = 300

    var body: some View {
        let all = model.mode == .demo ? demoSchemes : model.schemes
        let categories = Array(Set(all.map(\.shortCategory))).sorted()
        let filtered = filter(all)
        VStack(alignment: .leading, spacing: Space.m) {
            PageHeader(title: "Fund Explorer", subtitle: model.mode == .demo ? "\(all.count) demo schemes" : "\(FinanceFormat.plain(Decimal(all.count), digits: 0)) schemes from AMFI") {
                HStack(spacing: Space.s) {
                    Toggle("Direct, Growth only", isOn: $directOnly).toggleStyle(.checkbox)
                    Picker("Category", selection: $category) {
                        Text("All categories").tag("")
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    .fixedSize()
                }
            }
            if all.isEmpty {
                if model.isRefreshingAMFI {
                    LoadingState(label: "Downloading AMFI's scheme list…")
                } else {
                    ErrorState(title: "AMFI's scheme list isn't available", message: model.amfiError ?? "Not downloaded yet.") {
                        Task { await model.refreshAMFI() }
                    }
                }
            } else {
                Table(Array(filtered.prefix(Self.displayLimit)), selection: $selection) {
                    TableColumn("Scheme") { s in
                        HStack(spacing: Space.xs) {
                            Text(s.name).textStyle(.table)
                            if model.isWatched(s.code) { Pill(text: "Watching", tint: Palette.accent) }
                        }
                    }
                    .width(min: 240, ideal: 320)
                    TableColumn("Fund house") { Text($0.amc).textStyle(.table, color: Palette.textSecondary) }
                    TableColumn("Category") { Text($0.shortCategory).textStyle(.table) }
                    TableColumn("Plan") { Text([$0.plan, $0.option].compactMap { $0 }.joined(separator: " · ")).textStyle(.table, color: Palette.textSecondary) }
                    TableColumn("NAV") { ValueText(value: $0.nav, kind: .nav, missingReason: "AMFI published N.A.") }
                        .width(min: 70, ideal: 90).alignment(.trailing)
                    TableColumn("Date") { Text($0.date.map(FinanceFormat.shortDate) ?? "—").textStyle(.table, color: Palette.textSecondary) }
                        .width(min: 60, ideal: 70)
                }
                .hairlineBorder()
                .contextMenu(forSelectionType: String.self) { ids in
                    if let id = ids.first, let scheme = all.first(where: { $0.code == id }) {
                        if model.mode == .real {
                            if model.isWatched(id) {
                                Button("Remove from Watchlist") { model.remove(id) }
                            } else {
                                Button("Add to Watchlist") { _ = try? model.add([scheme]) }
                            }
                        }
                        Button("Open Fund") { model.open(id, tab: .history) }
                    }
                } primaryAction: { ids in
                    if let id = ids.first { model.open(id, tab: .history) }
                }
                .onChange(of: selection) { _, id in model.inspect(id) }
                Text(filtered.count > Self.displayLimit
                     ? "Showing \(Self.displayLimit) of \(filtered.count). Search to narrow down. Right-click a scheme to add it to your watchlist."
                     : "\(filtered.count) schemes. Right-click a scheme to add it to your watchlist.")
                    .textStyle(.caption)
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.l)
        .searchable(text: $query, prompt: "Name, fund house or scheme code")
    }

    private func filter(_ all: [SchemeRecord]) -> [SchemeRecord] {
        let base = all.filter { (category.isEmpty || $0.shortCategory == category) && (!directOnly || ($0.isDirect && $0.isGrowth)) }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base.sorted { $0.name < $1.name } }
        if Int(q) != nil { return base.filter { $0.code.hasPrefix(q) } }
        return FundMatcher.search(q, in: base, direct: nil, growthOnly: false, limit: Self.displayLimit).map(\.scheme)
    }

    /// Demo funds shown as schemes so the same table works in demo mode.
    private var demoSchemes: [SchemeRecord] {
        (model.data?.funds ?? []).map { f in
            SchemeRecord(code: f.code, isin: nil, name: f.name, plan: "Direct Plan", option: "Growth",
                         nav: model.data?.navHistory[f.code]?.last?.nav, date: model.data?.navHistory[f.code]?.last?.date,
                         amc: f.amc, category: "Equity Scheme - \(f.category)")
        }
    }
}
