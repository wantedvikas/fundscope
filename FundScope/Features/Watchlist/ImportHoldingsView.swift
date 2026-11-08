import FundScopeCore
import SwiftUI

/// Import a fund house's monthly portfolio file. Each sheet is matched to a watched fund and checked before saving.
struct ImportHoldingsView: View {
    var onClose: () -> Void
    @Environment(AppModel.self) private var model
    @State private var items: [Item] = []
    @State private var message: String?

    struct Item: Identifiable {
        let id = UUID()
        let fileName: String
        let parsed: DisclosureParser.Parsed
        var fundCode: String?
        var include: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Text("Import fund holdings").textStyle(.screenTitle)
                Text("Fund houses publish each fund's portfolio every month. Download it from their website (usually under Statutory Disclosures → Monthly Portfolio) and drop it here.")
                    .textStyle(.secondary)
            }
            ImportDropZone(title: "Drop monthly portfolio files",
                           message: "XLSX or CSV. Files with one sheet per fund work too; each sheet is matched to your watchlist.") { urls in
                urls.forEach(read)
            }
            .frame(height: 140)
            if items.isEmpty {
                Spacer()
            } else {
                List($items) { $item in
                    row($item)
                }
                .listStyle(.inset)
                .hairlineBorder()
            }
            HStack {
                if let message { Text(message).textStyle(.secondary).lineLimit(2) }
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
                let count = importable.count
                Button(count == 1 ? "Import 1 Portfolio" : "Import \(count) Portfolios") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(count == 0)
            }
        }
        .padding(Space.xl)
        .frame(minWidth: 780, minHeight: 560)
        #if DEBUG
        .onAppear {
            // UI tests can't drive the file panel; they pass files copied into the app container.
            UserDefaults.standard.string(forKey: "importHoldingsFixture")?
                .split(separator: "|").forEach { read(URL(filePath: String($0))) }
        }
        #endif
    }

    private var importable: [Item] {
        items.filter { $0.include && $0.fundCode != nil && $0.parsed.date != nil && !model.hasDisclosure($0.fundCode!, date: $0.parsed.date) }
    }

    @ViewBuilder private func row(_ item: Binding<Item>) -> some View {
        let p = item.wrappedValue.parsed
        HStack(alignment: .top, spacing: Space.m) {
            Toggle("Include", isOn: item.include).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(p.title).textStyle(.body)
                Text("\(item.wrappedValue.fileName)\(p.sheetName.isEmpty ? "" : " · \(p.sheetName)") · \(p.holdings.count) holdings · total \(FinanceFormat.percent(p.totalWeight, signed: false))")
                    .textStyle(.caption)
                ForEach(p.warnings, id: \.self) { Text($0).textStyle(.caption, color: Palette.warning) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(p.date.map(FinanceFormat.date) ?? "No date").textStyle(.table, color: p.date == nil ? Palette.warning : Palette.textPrimary)
                .frame(width: 90, alignment: .leading)
            Picker("Fund", selection: item.fundCode) {
                Text("Not in watchlist").tag(String?.none)
                ForEach(model.watched) { w in Text(w.fund.name).tag(Optional(w.fund.code)) }
            }
            .labelsHidden()
            .frame(width: 240)
            status(item.wrappedValue)
                .frame(width: 110, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func status(_ item: Item) -> some View {
        if item.parsed.date == nil {
            Pill(text: "No date", tint: Palette.warning)
        } else if item.fundCode == nil {
            Pill(text: "Pick a fund", tint: Palette.textSecondary)
        } else if model.hasDisclosure(item.fundCode!, date: item.parsed.date) {
            Pill(text: "Already imported", tint: Palette.textSecondary)
        } else {
            Pill(text: "New", tint: Palette.positive)
        }
    }

    private func read(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let parsed = DisclosureParser.parse(try TableReader.read(url))
            guard !parsed.isEmpty else {
                message = "No portfolio table found in \(url.lastPathComponent). Look for a table with ISIN and “% to Net Assets” columns."
                return
            }
            let watchedRecords = model.watched.compactMap { model.directory[$0.fund.code] }
            items += parsed.map { p in
                // The disclosure covers every plan of the fund, so match on the name only, and only when the names
                // have exactly the same words; anything looser (Multi Cap vs Large Cap) is left for the user to pick.
                let code = watchedRecords.first { FundMatcher.sameScheme($0.name, p.title) }?.code
                return Item(fileName: url.lastPathComponent, parsed: p, fundCode: code, include: code != nil)
            }
            message = "Read \(parsed.count) fund\(parsed.count == 1 ? "" : "s") from \(url.lastPathComponent)."
        } catch {
            message = error.localizedDescription
        }
    }

    private func save() {
        var saved = 0
        var failed: [String] = []
        for item in importable {
            do {
                if try model.saveDisclosure(item.parsed, fundCode: item.fundCode!, fileName: item.fileName) == .saved { saved += 1 }
            } catch {
                failed.append(item.parsed.title)
            }
        }
        message = failed.isEmpty ? "Imported \(saved) monthly portfolio\(saved == 1 ? "" : "s")." : "Imported \(saved). Couldn't save: \(failed.joined(separator: ", "))."
    }
}
