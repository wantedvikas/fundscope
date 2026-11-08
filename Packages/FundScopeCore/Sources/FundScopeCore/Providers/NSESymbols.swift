import Foundation

/// ISIN → NSE trading symbol. Kite quotes stocks by symbol ("NSE:HDFCBANK") and its instrument list has no ISINs,
/// while fund disclosures list ISINs. NSE's public equity list bridges the two.
/// Checked 2026-10-29: EQUITY_L ~2,600 rows, header `SYMBOL,NAME OF COMPANY, SERIES, …, ISIN NUMBER, FACE VALUE`;
/// eq_etfseclist ~360 rows, header `Symbol,Underlying Asset,SecurityName,…,ISINNumber,…`. Neither lists REITs or InvITs.
/// ind_nifty50list (checked 2026-10-30): 50 rows, header `Company Name,Industry,Symbol,Series,ISIN Code`.
public enum NSESymbols {
    public static let niftyFiftyURL = URL(string: "https://nsearchives.nseindia.com/content/indices/ind_nifty50list.csv")!
    public static let urls = [
        URL(string: "https://archives.nseindia.com/content/equities/EQUITY_L.csv")!,
        URL(string: "https://nsearchives.nseindia.com/content/equities/eq_etfseclist.csv")!,
        niftyFiftyURL,
    ]

    public struct IndexStock: Identifiable, Hashable, Sendable {
        public let name: String
        public let industry: String
        public let symbol: String
        public let isin: String
        public var id: String { symbol }
    }

    /// An NSE index constituents file (ind_nifty50list.csv). Rows without a symbol or a valid ISIN are skipped.
    public static func constituents(_ text: String) -> [IndexStock] {
        let rows = CSVReader.parse(text)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).uppercased() }),
              let nameCol = header.firstIndex(of: "COMPANY NAME"), let industryCol = header.firstIndex(of: "INDUSTRY"),
              let symbolCol = header.firstIndex(of: "SYMBOL"), let isinCol = header.firstIndex(where: { $0.contains("ISIN") })
        else { return [] }
        return rows.dropFirst().compactMap { row in
            guard row.count > max(nameCol, industryCol, symbolCol, isinCol) else { return nil }
            let cell = { (i: Int) in row[i].trimmingCharacters(in: .whitespaces) }
            guard !cell(symbolCol).isEmpty, ValueParser.isISIN(cell(isinCol)) else { return nil }
            return IndexStock(name: cell(nameCol), industry: cell(industryCol), symbol: cell(symbolCol), isin: cell(isinCol))
        }
    }

    /// Columns are found by header name, so reordering doesn't break it. Rows without a valid ISIN are skipped.
    public static func parse(_ text: String) -> [String: String] {
        let rows = CSVReader.parse(text)
        guard let header = rows.first?.map({ $0.trimmingCharacters(in: .whitespaces).uppercased() }),
              let symbolCol = header.firstIndex(of: "SYMBOL"),
              let isinCol = header.firstIndex(where: { $0.contains("ISIN") })
        else { return [:] }
        var map: [String: String] = [:]
        for row in rows.dropFirst() where row.count > max(symbolCol, isinCol) {
            let isin = row[isinCol].trimmingCharacters(in: .whitespaces)
            let symbol = row[symbolCol].trimmingCharacters(in: .whitespaces)
            if ValueParser.isISIN(isin), !symbol.isEmpty { map[isin] = symbol }
        }
        return map
    }

    public static func download(_ url: URL, session: URLSession = .shared) async throws -> String {
        var request = URLRequest(url: url)
        // NSE rejects requests without a browser-like user agent.
        request.setValue("Mozilla/5.0 (Macintosh) FundScope", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(decoding: data, as: UTF8.self)
        guard status == 200, !parse(text).isEmpty else { throw URLError(.badServerResponse) }
        return text
    }
}
