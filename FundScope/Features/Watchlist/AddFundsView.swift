import FundScopeCore
import SwiftUI

/// Add funds by searching, by pasting names, or by reading names from a file. Only names are read.
struct AddFundsView: View {
    var onClose: () -> Void
    @Environment(AppModel.self) private var model
    @State private var tab = Tab.search
    @State private var query = ""
    @State private var direct = true
    @State private var pasted = ""
    @State private var resolved: [Resolution] = []
    @State private var message: String?

    enum Tab: String, CaseIterable { case search = "Search", list = "Paste a list" }

    struct Resolution: Identifiable {
        let id = UUID()
        let typed: String
        let direct: Bool
        var choice: SchemeRecord?
        let alternatives: [SchemeRecord]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    Text("Add funds").textStyle(.screenTitle)
                    Text("Only fund names are used. FundScope never asks what you invested.").textStyle(.secondary)
                }
                Spacer()
                Picker("Mode", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            if model.schemes.isEmpty {
                directoryState
            } else {
                switch tab {
                case .search: searchTab
                case .list: listTab
                }
            }
            HStack {
                if let message { Text(message).textStyle(.secondary) }
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
            }
        }
        .padding(Space.xl)
        .frame(minWidth: 720, minHeight: 540)
        #if DEBUG
        .onAppear {
            // UI tests can't synthesise typing on every Mac; they pass the names instead.
            if let names = UserDefaults.standard.string(forKey: "prefillFundNames") {
                tab = .list
                pasted = names.replacingOccurrences(of: "|", with: "\n")
            }
        }
        #endif
    }

    @ViewBuilder private var directoryState: some View {
        if model.isRefreshingAMFI {
            LoadingState(label: "Downloading AMFI's scheme list…")
        } else {
            ErrorState(title: "AMFI's scheme list isn't available",
                       message: model.amfiError ?? "FundScope needs AMFI's public scheme list to find funds by name.",
                       retry: { Task { await model.refreshAMFI() } })
        }
    }

    // MARK: Search

    private var searchTab: some View {
        let results = FundMatcher.search(query, in: model.schemes, direct: direct, limit: 30)
        return VStack(alignment: .leading, spacing: Space.s) {
            HStack {
                TextField("Fund name, e.g. Parag Parikh Flexi Cap", text: $query)
                    .textFieldStyle(.roundedBorder)
                Picker("Plan", selection: $direct) {
                    Text("Direct").tag(true)
                    Text("Regular").tag(false)
                }
                .fixedSize()
            }
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("\(FinanceFormat.plain(Decimal(model.schemes.count), digits: 0)) schemes from AMFI. Showing Growth options.").textStyle(.caption)
                Spacer()
            } else if results.isEmpty {
                EmptyState(symbol: "magnifyingglass", title: "No matches", message: "Try fewer words, or the fund house's full name.")
            } else {
                List(results, id: \.scheme.code) { match in
                    SchemeRow(scheme: match.scheme, isWatched: model.isWatched(match.scheme.code)) { add([match.scheme]) }
                }
                .listStyle(.inset)
                .hairlineBorder()
            }
        }
    }

    // MARK: Paste / file

    private var listTab: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if resolved.isEmpty {
                Text("One fund per line. Short names like “ICICI Pru” or “WOC” work.").textStyle(.caption)
                TextEditor(text: $pasted)
                    .font(TextStyle.body.font)
                    .scrollContentBackground(.hidden)
                    .padding(Space.xs)
                    .hairlineBorder()
                ImportDropZone(title: "Or read names from a file",
                               message: "A holdings CSV or XLSX from Coin, Console or Tickertape. Only the fund name and plan columns are read; amounts are ignored.") { urls in
                    if let url = urls.first { readNames(url) }
                }
                .frame(height: 150)
                HStack {
                    Spacer()
                    Button("Find Funds") { resolve(pasted.split(whereSeparator: \.isNewline).map { (String($0), true) }) }
                        .buttonStyle(.borderedProminent)
                        .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            } else {
                Text("Check each match, then add them.").textStyle(.caption)
                List($resolved) { $item in
                    HStack(spacing: Space.m) {
                        Text(item.typed).textStyle(.body).frame(width: 240, alignment: .leading).lineLimit(1)
                        Image(systemName: "arrow.right").foregroundStyle(Palette.textTertiary)
                        Picker("Match", selection: $item.choice) {
                            Text("Don't add").tag(SchemeRecord?.none)
                            ForEach(item.alternatives) { s in Text("\(s.name) · \(s.plan ?? "")").tag(Optional(s)) }
                        }
                        .labelsHidden()
                        if item.choice == nil {
                            Pill(text: item.alternatives.isEmpty ? "Not found" : "Pick one", tint: Palette.warning)
                        } else if model.isWatched(item.choice!.code) {
                            Pill(text: "Already watched", tint: Palette.textSecondary)
                        }
                    }
                }
                .listStyle(.inset)
                .hairlineBorder()
                HStack {
                    Button("Back") { resolved = [] }
                    Spacer()
                    let count = resolved.compactMap(\.choice).filter { !model.isWatched($0.code) }.count
                    Button("Add \(count) Funds") {
                        add(resolved.compactMap(\.choice))
                        resolved = []
                        pasted = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(count == 0)
                }
            }
        }
    }

    private func readNames(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let entries = FundListReader.entries(try TableReader.read(url))
            guard !entries.isEmpty else { message = "No “Fund Name” or “Scheme Name” column found in that file."; return }
            message = "Read \(entries.count) fund names from \(url.lastPathComponent). Nothing else from the file was kept."
            resolve(entries.map { ($0.name, $0.direct ?? true) })
        } catch {
            message = error.localizedDescription
        }
    }

    private func resolve(_ names: [(String, Bool)]) {
        resolved = names.compactMap { name, direct in
            let typed = name.trimmingCharacters(in: .whitespaces)
            guard !typed.isEmpty else { return nil }
            let matches = FundMatcher.search(typed, in: model.schemes, direct: direct, limit: 5).map(\.scheme)
            return Resolution(typed: typed, direct: direct, choice: FundMatcher.bestMatch(typed, in: model.schemes, direct: direct), alternatives: matches)
        }
    }

    private func add(_ schemes: [SchemeRecord]) {
        do {
            let added = try model.add(schemes)
            message = added == 1 ? "Added 1 fund." : "Added \(added) funds."
        } catch {
            message = "Couldn't add: \(error.localizedDescription)"
        }
    }
}

/// One AMFI scheme with an Add button.
struct SchemeRow: View {
    let scheme: SchemeRecord
    let isWatched: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scheme.name).textStyle(.body)
                Text("\(scheme.amc) · \(scheme.shortCategory) · \(scheme.plan ?? "") · \(scheme.option ?? "")").textStyle(.caption)
            }
            Spacer()
            ValueText(value: scheme.nav, kind: .nav)
            if isWatched {
                Pill(text: "Watching", tint: Palette.accent)
            } else {
                Button("Add", action: onAdd)
            }
        }
        .padding(.vertical, 2)
    }
}
