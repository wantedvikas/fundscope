import Foundation

/// Reads AMC monthly portfolio statements (SEBI format). Layouts differ by fund house, so columns are found
/// by header text and asset types by the section headings above each block of rows.
/// Checked against PPFAS (Sep and Aug 2026). **[verify]** other AMCs' files as they're imported.
public enum DisclosureParser {
    public struct Parsed: Identifiable, Hashable, Sendable {
        public var id: String { sheetName + title }
        public let sheetName: String
        /// Fund name printed above the table, without the "(An open-ended …)" description.
        public let title: String
        public let date: Date?
        public let holdings: [DisclosedHolding]
        public let warnings: [String]

        public var totalWeight: Decimal { holdings.reduce(0) { $0 + $1.weight } }
    }

    public static func parse(_ sheets: [RawSheet]) -> [Parsed] {
        sheets.compactMap(parse)
    }

    static func parse(_ sheet: RawSheet) -> Parsed? {
        let rows = sheet.rows
        guard let headerIndex = rows.prefix(40).firstIndex(where: isHeader) else { return nil }
        let headers = rows[headerIndex].map { $0.lowercased() }
        func column(_ test: (String) -> Bool) -> Int? { headers.firstIndex(where: test) }
        guard let isinCol = column({ $0.contains("isin") }),
              let weightCol = column(isWeightHeader),
              let nameCol = column({ $0.contains("name of") || $0.contains("instrument") || $0.contains("issuer") || $0.contains("company") || $0.contains("security") })
        else { return nil }
        let industryCol = column { $0.contains("industry") || $0.contains("rating") || $0.contains("sector") }
        let quantityCol = column { $0.contains("quantity") }

        let preamble = rows.prefix(headerIndex).flatMap { $0 }.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        // The first line naming a fund, skipping the fund house's own name ("ICICI Prudential Mutual Fund").
        let title = preamble.first { $0.localizedCaseInsensitiveContains("fund") && !$0.lowercased().hasSuffix("mutual fund") }
            .map(cleanTitle) ?? sheet.name
        let date = preamble.lazy.compactMap(statementDate).first

        func cell(_ row: [String], _ col: Int?) -> String {
            guard let col, row.indices.contains(col) else { return "" }
            return row[col].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var section = AssetType.equity
        // Some AMCs (ICICI) print subtotals on heading rows; only a cash heading without its own weight
        // means the unnamed rows below it (PPFAS "TRP_011026") are holdings.
        var cashSectionWithoutSubtotal = false
        var drafts: [(holding: (String, String?, String?, AssetType, Decimal?), weight: Weight)] = []
        var grandTotal: Weight?
        var warnings: [String] = []

        for row in rows.dropFirst(headerIndex + 1) {
            let isinText = cell(row, isinCol).uppercased()
            let isin = ValueParser.isISIN(isinText) ? isinText : nil
            // Headings and totals may sit in another column than names (HDFC puts them under ISIN).
            var name = cell(row, nameCol)
            if name.isEmpty, isin == nil { name = row.prefix(nameCol + 1).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? "" }
            let lower = name.lowercased()
            let weight = Weight(cell(row, weightCol))
            if lower.hasPrefix("grand total") || lower.hasPrefix("total net assets") { grandTotal = weight; break }
            guard !name.isEmpty else { continue }
            if lower.hasPrefix("sub total") || lower.hasPrefix("subtotal") || lower == "total" { continue }

            let type: AssetType
            if let isin {
                guard weight != nil else { continue }
                type = assetType(isin: isin, section: section)
            } else {
                let isCash = ["net receivable", "net current", "cash", "margin", "treps", "repo", "tri-party", "cblo"].contains(where: lower.contains)
                if let next = sectionType(lower) {
                    section = next
                    cashSectionWithoutSubtotal = next == .cash && weight == nil
                }
                let isFuture = section == .derivative && (lower.contains("future") || lower.contains("option"))
                // Unnamed-by-ISIN rows count only when they're clearly cash or a futures/options contract;
                // anything else is a heading or subtotal. A missed real holding still shows up in the
                // "weights don't add up to 100%" warning.
                guard weight != nil, isCash || isFuture || (section == .cash && cashSectionWithoutSubtotal) else { continue }
                type = isFuture ? .derivative : .cash
            }
            guard let weight else { continue }
            let industry = cell(row, industryCol).trimmingCharacters(in: CharacterSet(charactersIn: "#^*~ "))
            drafts.append(((name, isin, industry.isEmpty ? nil : industry, type, ValueParser.number(cell(row, quantityCol))), weight))
        }

        guard !drafts.isEmpty else { return nil }
        // Weights are either fractions (0.0775) or percents (7.75); text like "$0.00%" is always a percent.
        let numericTotal = drafts.filter { !$0.weight.isPercentText }.reduce(Decimal(0)) { $0 + $1.weight.value }
        let isFraction = grandTotal.map { !$0.isPercentText && $0.value <= 2 } ?? (numericTotal <= 2)
        // A stock with a future on the same company in this table is an arbitrage pair: both legs are hedged (flat).
        let futureCompanies = Set(drafts.filter { $0.holding.3 == .derivative }.map { futureCompany($0.holding.0) })
        let hedgedStocks = Set(drafts.filter { $0.holding.3 == .equity }.map { companyKey($0.holding.0) }).intersection(futureCompanies)
        var holdings = drafts.map { d -> DisclosedHolding in
            let w = d.weight.isPercentText || !isFraction ? d.weight.value : d.weight.value * 100
            var (name, isin, industry, type, quantity) = d.holding
            if type == .equity, hedgedStocks.contains(companyKey(name)) { type = .hedged }
            if type == .derivative, hedgedStocks.contains(futureCompany(name)) { type = .hedged }
            let security = isin.map { SecurityInfo(isin: $0, name: name, symbol: "", sector: industry ?? "Unclassified", marketCap: nil) }
            return DisclosedHolding(rawName: name, security: type == .cash || type == .debt ? nil : security,
                                    assetType: type, weight: w.rounded(4), quantity: quantity)
        }
        var total = holdings.reduce(Decimal(0)) { $0 + $1.weight }
        // Some files (Bandhan) print a "Net Current Assets" summary that their own grand total leaves out.
        // If one cash line accounts for exactly the gap to the file's total, it's that summary, not a holding.
        let fileTotal: Decimal = 100
        if grandTotal != nil, abs(total - fileTotal) > Decimal(string: "0.05")!,
           let i = holdings.lastIndex(where: { $0.assetType == .cash && $0.security == nil && abs($0.weight - (total - fileTotal)) <= Decimal(string: "0.02")! }) {
            total -= holdings[i].weight
            holdings.remove(at: i)
        }
        if abs(total - 100) > 1 { warnings.append("Weights add up to \(FinanceFormat.percent(total, signed: false)), not 100%.") }
        if date == nil { warnings.append("No “as on” date found in the file.") }
        return Parsed(sheetName: sheet.name, title: title, date: date, holdings: holdings, warnings: warnings)
    }

    // MARK: Helpers

    /// "HDFC Bank Limited November 2026 Future" → "hdfc bank limited".
    static func futureCompany(_ name: String) -> String {
        let pattern = #"\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+\d{4}\s+(futur|option).*$"#
        return companyKey(name.lowercased().replacingOccurrences(of: pattern, with: "", options: .regularExpression))
    }

    /// Spelling-insensitive company name: "Info Edge (India) Ltd ^^^" and "Info Edge India Limited" → "info edge india limited".
    static func companyKey(_ name: String) -> String {
        let chars: [Character] = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : Character(" ") }
        return chars.split(separator: " ").map { $0 == ["l", "t", "d"] ? "limited" : String($0) }.joined(separator: " ")
    }

    static func isHeader(_ row: [String]) -> Bool {
        let cells = row.map { $0.lowercased() }
        return cells.contains { $0.contains("isin") } && cells.contains(where: isWeightHeader)
    }

    static func isWeightHeader(_ text: String) -> Bool {
        // Headers often wrap ("% to Net⏎ Assets"); compare with single spaces.
        let t = text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return t.contains("%") && (t.contains("net asset") || t.contains("nav") || t.contains("aum"))
    }

    /// Section headings → the asset type of the rows below them.
    static func sectionType(_ heading: String) -> AssetType? {
        if heading.contains("foreign") || heading.contains("overseas") { return .foreignEquity }
        if heading.contains("arbitrage") || heading.contains("hedged") { return .hedged }
        if heading.contains("reit") || heading.contains("invit") { return .other }
        if heading.contains("derivative") || heading.contains("future") || heading.contains("option") { return .derivative }
        if heading.contains("mutual fund") { return .fundUnits }
        if heading.contains("treps") || heading.contains("repo") || heading.contains("tri-party") || heading.contains("cash") { return .cash }
        if ["money market", "certificate of deposit", "commercial paper", "treasury bill", "debt", "bond", "debenture",
            "government securit", "state development", "corporate", "securitised", "g-sec"].contains(where: heading.contains) { return .debt }
        if heading.contains("equity") || heading.contains("listed") { return .equity }
        return nil
    }

    /// The ISIN decides when it's clearer than the section: non-Indian ISINs are foreign, INF are fund units.
    static func assetType(isin: String, section: AssetType) -> AssetType {
        if !isin.hasPrefix("IN") { return .foreignEquity }
        if isin.hasPrefix("INF"), section == .equity { return .fundUnits }
        if section == .foreignEquity { return .foreignEquity }
        return section
    }

    static func cleanTitle(_ text: String) -> String {
        let base = text.components(separatedBy: "(").first ?? text
        return base.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "-–:")))
    }

    static let titleDateFormats = ["MMMM d, yyyy", "MMMM dd, yyyy", "MMM d, yyyy", "d MMMM yyyy", "dd MMMM yyyy", "dd-MMM-yyyy",
                                   "dd.MM.yyyy", "dd/MM/yyyy", "dd-MM-yyyy", "yyyy-MM-dd", "d-MMM-yyyy", "dd MMM yyyy"]

    /// "Monthly Portfolio Statement as on September 30, 2026" → 30 Sep 2026.
    static func statementDate(_ text: String) -> Date? {
        let lower = text.lowercased()
        guard let range = lower.range(of: "as on") ?? lower.range(of: "as of") ?? lower.range(of: "as at") else { return nil }
        // "Sep 30,2026" → "Sep 30, 2026" so one set of formats covers both spellings.
        let tail = text[range.upperBound...].replacingOccurrences(of: ",", with: ", ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":")))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = MarketCalendar.ist
        formatter.isLenient = false
        // Try progressively shorter prefixes so trailing text ("(Unaudited)") doesn't block parsing.
        let words = tail.split(separator: " ")
        for count in stride(from: min(words.count, 4), through: 1, by: -1) {
            let candidate = words.prefix(count).joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: ".,;)"))
            for format in titleDateFormats {
                formatter.dateFormat = format
                if let d = formatter.date(from: candidate) { return MarketCalendar().calendar.startOfDay(for: d) }
            }
        }
        return nil
    }

    struct Weight: Hashable {
        let value: Decimal
        let isPercentText: Bool

        init?(_ text: String) {
            let t = text.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !["nil", "-", "—", "n.a."].contains(t.lowercased()) else { return nil }
            isPercentText = t.contains("%")
            guard let v = ValueParser.number(t.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: "%", with: "")) else { return nil }
            value = v
        }
    }
}
