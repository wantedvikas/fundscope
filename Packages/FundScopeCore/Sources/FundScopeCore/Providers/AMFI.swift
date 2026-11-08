import Foundation

/// One scheme from AMFI's daily NAV file.
public struct SchemeRecord: Identifiable, Hashable, Sendable {
    public var id: String { code }
    public let code: String
    public let isin: String?
    public let name: String
    public let plan: String?
    public let option: String?
    /// Nil when AMFI publishes "N.A.", never treated as zero.
    public let nav: Decimal?
    public let date: Date?
    public let amc: String
    /// Full AMFI category, e.g. "Equity Scheme - Small Cap Fund".
    public let category: String

    public init(code: String, isin: String?, name: String, plan: String?, option: String?, nav: Decimal?, date: Date?, amc: String, category: String) {
        self.code = code
        self.isin = isin
        self.name = name
        self.plan = plan
        self.option = option
        self.nav = nav
        self.date = date
        self.amc = amc
        self.category = category
    }

    public var isDirect: Bool { (plan ?? name).localizedCaseInsensitiveContains("direct") }

    public var isGrowth: Bool {
        let text = (option ?? name).lowercased()
        return text.contains("growth") && !text.contains("idcw") && !text.contains("dividend") && !text.contains("bonus")
    }

    /// Equity and hybrid schemes are candidates for live estimates; coverage rules decide the rest.
    public var isEstimableCategory: Bool { category.hasPrefix("Equity Scheme") || category.hasPrefix("Hybrid Scheme") }

    /// "Small Cap Fund" from "Equity Scheme - Small Cap Fund".
    public var shortCategory: String {
        category.components(separatedBy: " - ").last?.trimmingCharacters(in: .whitespaces) ?? category
    }

    public var fundInfo: FundInfo {
        FundInfo(code: code, name: name, amc: amc, category: shortCategory, plan: isDirect ? .direct : .regular, isEstimable: isEstimableCategory)
    }
}

/// AMFI's public NAV file. FundScope sends nothing but a plain GET; no personal data.
public enum AMFI {
    // Checked 2026-10-29: www.amfiindia.com/spages/NAVAll.txt redirects here.
    public static let navAllURL = URL(string: "https://portal.amfiindia.com/spages/NAVAll.txt")!

    public enum FetchError: Error, LocalizedError {
        case badResponse(Int)
        case unexpectedFormat

        public var errorDescription: String? {
            switch self {
            case .badResponse(let code): "AMFI responded with HTTP \(code)."
            case .unexpectedFormat: "AMFI's NAV file wasn't in the expected format."
            }
        }
    }

    public static func download(session: URLSession = .shared) async throws -> String {
        let (data, response) = try await session.data(from: navAllURL)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw FetchError.badResponse(status) }
        let text = String(decoding: data, as: UTF8.self)
        guard text.hasPrefix("Scheme Code"), !parse(text).isEmpty else { throw FetchError.unexpectedFormat }
        return text
    }

    /// Parses NAVAll.txt. Column positions come from the header line, so both the older 6-column
    /// and the current 8-column (with Plan and Option) layouts work.
    public static func parse(_ text: String) -> [SchemeRecord] {
        var records: [SchemeRecord] = []
        var columns: [String: Int] = [:]
        var amc = ""
        var category = ""
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = MarketCalendar.ist
        formatter.dateFormat = "dd-MMM-yyyy"

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let fields = line.components(separatedBy: ";")
            if line.hasPrefix("Scheme Code") {
                for (i, header) in fields.enumerated() {
                    let h = header.lowercased()
                    if h.hasPrefix("scheme code") { columns["code"] = i }
                    else if h.contains("isin") && columns["isin"] == nil { columns["isin"] = i }
                    else if h.contains("scheme name") || h == "nav name" { columns["name"] = i }
                    else if h == "plan" { columns["plan"] = i }
                    else if h == "option" { columns["option"] = i }
                    else if h.contains("net asset value") { columns["nav"] = i }
                    else if h == "date" { columns["date"] = i }
                }
                continue
            }
            if fields.count == 1 {
                // Section lines: "Open Ended Schemes(Equity Scheme - Small Cap Fund)" or an AMC name.
                if let open = line.firstIndex(of: "("), line.contains("Schemes"), line.hasSuffix(")") {
                    category = String(line[line.index(after: open)..<line.index(before: line.endIndex)]).trimmingCharacters(in: .whitespaces)
                } else {
                    amc = line
                }
                continue
            }
            func field(_ key: String) -> String? {
                guard let i = columns[key], fields.indices.contains(i) else { return nil }
                let v = fields[i].trimmingCharacters(in: .whitespaces)
                return v.isEmpty || v == "-" ? nil : v
            }
            guard let code = field("code"), Int(code) != nil, let name = field("name") else { continue }
            records.append(SchemeRecord(
                code: code, isin: field("isin"), name: name, plan: field("plan"), option: field("option"),
                nav: field("nav").flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }.flatMap { $0 > 0 ? $0 : nil },
                date: field("date").flatMap { formatter.date(from: $0) }, amc: amc, category: category))
        }
        return records
    }
}

/// Finds schemes by the name a person would type, e.g. "ICICI Pru Large Cap" or "WOC Flexi Cap".
public enum FundMatcher {
    static let aliases: [String: [String]] = [
        "pru": ["prudential"], "woc": ["whiteoak", "capital"], "ppfas": ["parag", "parikh"],
        "smallcap": ["small", "cap"], "midcap": ["mid", "cap"], "largecap": ["large", "cap"],
        "flexicap": ["flexi", "cap"], "multicap": ["multi", "cap"], "absl": ["aditya", "birla", "sun", "life"],
    ]
    static let ignored: Set<String> = ["fund", "the", "plan", "direct", "regular", "growth", "option", "scheme"]

    static func tokens(_ text: String) -> [String] {
        // "(erstwhile Bluechip Fund)" and similar notes shouldn't affect matching.
        var cleaned = text.lowercased()
        if let r = cleaned.range(of: #"\(erstwhile[^)]*\)"#, options: .regularExpression) { cleaned.removeSubrange(r) }
        cleaned = cleaned.replacingOccurrences(of: "&", with: " and ")
        let chars: [Character] = cleaned.map { $0.isLetter || $0.isNumber ? $0 : Character(" ") }
        let words = chars.split(separator: " ").map { String($0) }
        return words.flatMap { aliases[$0] ?? [$0] }.filter { !ignored.contains($0) }
    }

    public struct Match: Hashable, Sendable {
        public let scheme: SchemeRecord
        /// 0…1: share of the typed words found in the scheme name.
        public let score: Double
    }

    /// Best matches first. Default: Direct plan, Growth option (what Zerodha Coin offers).
    public static func search(_ query: String, in records: [SchemeRecord], direct: Bool? = true, growthOnly: Bool = true, limit: Int = 8) -> [Match] {
        let q = Set(tokens(query))
        guard !q.isEmpty else { return [] }
        var scored: [(match: Match, extra: Int)] = []
        for r in records where (direct == nil || r.isDirect == direct) && (!growthOnly || r.isGrowth) {
            let name = Set(tokens(r.name))
            let hit = q.intersection(name).count
            guard hit > 0 else { continue }
            // Extra words in the scheme name break ties: "Large Cap" beats "Large & Mid Cap" for "Large Cap".
            scored.append((Match(scheme: r, score: Double(hit) / Double(q.count)), name.subtracting(q).count))
        }
        scored.sort { $0.match.score != $1.match.score ? $0.match.score > $1.match.score : $0.extra < $1.extra }
        return scored.prefix(limit).map(\.match)
    }

    /// True when two names describe the same scheme: the same words on both sides, ignoring "Fund", plan/option words
    /// and "(erstwhile …)". "Nippon India Multi Cap Fund" is *not* "Nippon India Large Cap Fund", though 3 of 4 words match.
    public static func sameScheme(_ a: String, _ b: String) -> Bool {
        let ta = Set(tokens(a)), tb = Set(tokens(b))
        return !ta.isEmpty && ta == tb
    }

    /// The single best match when every typed word is found; nil means the user should pick.
    public static func bestMatch(_ query: String, in records: [SchemeRecord], direct: Bool? = true) -> SchemeRecord? {
        guard let first = search(query, in: records, direct: direct, limit: 1).first, first.score == 1 else { return nil }
        return first.scheme
    }
}

/// Reads fund names from a holdings-style CSV/XLSX. Only the name and plan columns are read;
/// amounts, units and returns in the file are ignored and never stored.
public enum FundListReader {
    public struct Entry: Hashable, Sendable {
        public let name: String
        /// From a "Plan Type" column when present.
        public let direct: Bool?
    }

    static let nameHeaders = ["fund name", "scheme name", "scheme", "fund", "symbol"]

    public static func entries(_ sheets: [RawSheet]) -> [Entry] {
        for sheet in sheets {
            for (index, row) in sheet.rows.prefix(30).enumerated() {
                let headers = row.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                guard let nameCol = nameHeaders.lazy.compactMap({ headers.firstIndex(of: $0) }).first else { continue }
                let planCol = headers.firstIndex { $0 == "plan type" || $0 == "plan" }
                return sheet.rows.dropFirst(index + 1).compactMap { r in
                    guard r.indices.contains(nameCol) else { return nil }
                    let name = r[nameCol].trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty, !["total", "grand total"].contains(name.lowercased()) else { return nil }
                    let plan = planCol.flatMap { r.indices.contains($0) ? r[$0].lowercased() : nil }
                    return Entry(name: name, direct: plan.map { $0.contains("direct") ? true : $0.contains("regular") ? false : nil } ?? nil)
                }
            }
        }
        return []
    }
}
