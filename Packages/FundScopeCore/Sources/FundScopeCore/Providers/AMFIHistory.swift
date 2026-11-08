import Foundation

/// Per-scheme NAV history from the API behind AMFI's public "NAV History" page.
/// Checked 2026-10-29: `sd_id` is the AMFI scheme code; a request must span less than 5 years;
/// an unknown scheme returns `{"message":"No records to display"}`; a bad range returns HTTP 400 `{"error": …}`.
public enum AMFIHistory {
    public static let maxSpanYears = 3

    public enum FetchError: Error, LocalizedError, Equatable {
        case server(String)
        case badResponse(Int)

        public var errorDescription: String? {
            switch self {
            case .server(let message): "AMFI: \(message)"
            case .badResponse(let code): "AMFI responded with HTTP \(code)."
            }
        }
    }

    static let dayFormat: Date.ISO8601FormatStyle = Date.ISO8601FormatStyle(timeZone: MarketCalendar.ist).year().month().day()

    public static func url(code: String, from: Date, to: Date) -> URL {
        var c = URLComponents(string: "https://www.amfiindia.com/api/nav-history")!
        c.queryItems = [
            URLQueryItem(name: "query_type", value: "historical_period"),
            URLQueryItem(name: "from_date", value: from.formatted(dayFormat)),
            URLQueryItem(name: "to_date", value: to.formatted(dayFormat)),
            URLQueryItem(name: "sd_id", value: code),
        ]
        return c.url!
    }

    public static func fetch(code: String, from: Date, to: Date, session: URLSession = .shared) async throws -> [NAVPoint] {
        let (data, response) = try await session.data(from: url(code: code, from: from, to: to))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            if let error = try? JSONDecoder().decode(Envelope.self, from: data).error { throw FetchError.server(error) }
            throw FetchError.badResponse(status)
        }
        return try parse(data)
    }

    struct Envelope: Decodable {
        struct Body: Decodable { let nav_groups: [Group] }
        struct Group: Decodable { let historical_records: [Record] }
        struct Record: Decodable {
            let date: String
            /// Decoded from the JSON number text, so 88.8018 stays exactly 88.8018.
            let nav: Decimal?
        }
        let data: Body?
        let message: String?
        let error: String?
    }

    /// Official NAV points, oldest first. "No records" is an empty result, not an error.
    public static func parse(_ data: Data) throws -> [NAVPoint] {
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        if let error = envelope.error { throw FetchError.server(error) }
        let records = envelope.data?.nav_groups.first?.historical_records ?? []
        return records.compactMap { r in
            guard let nav = r.nav, nav > 0, let date = try? Date(r.date, strategy: dayFormat) else { return nil }
            return NAVPoint(date: date, nav: nav)
        }
        .sorted { $0.date < $1.date }
    }

    /// Date ranges still missing for a fund, newest first, each shorter than the API limit.
    /// Fills the gap after the newest stored NAV and the history before the oldest, back to `years`.
    public static func missingRanges(earliest: Date?, latest: Date?, today: Date, years: Int = 5,
                                     market: MarketCalendar = MarketCalendar()) -> [(from: Date, to: Date)] {
        let calendar = market.calendar
        let day = { calendar.startOfDay(for: $0) }
        let end = day(today)
        let start = calendar.date(byAdding: .day, value: 1, to: calendar.date(byAdding: .year, value: -years, to: end)!)!
        var gaps: [(Date, Date)] = []
        if let latest, let earliest {
            // Today's NAV comes from the daily file; only fetch a gap if trading days were missed.
            if day(latest) < market.previousTradingDay(before: end) {
                gaps.append((calendar.date(byAdding: .day, value: 1, to: day(latest))!, end))
            }
            // A week of slack: AMFI history starts on a trading day, not exactly on `start`.
            let beforeEarliest = calendar.date(byAdding: .day, value: -1, to: day(earliest))!
            if calendar.date(byAdding: .day, value: 7, to: start)! < day(earliest) { gaps.append((start, beforeEarliest)) }
        } else {
            gaps.append((start, end))
        }
        // Split into chunks of at most `maxSpanYears`, newest first so recent data arrives first.
        var chunks: [(from: Date, to: Date)] = []
        for (from, to) in gaps {
            var chunkEnd = to
            while chunkEnd >= from {
                let candidate = calendar.date(byAdding: .day, value: 1, to: calendar.date(byAdding: .year, value: -maxSpanYears, to: chunkEnd)!)!
                let chunkStart = max(from, candidate)
                chunks.append((chunkStart, chunkEnd))
                chunkEnd = calendar.date(byAdding: .day, value: -1, to: chunkStart)!
            }
        }
        return chunks
    }
}
