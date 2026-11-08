import Foundation
import SwiftData

/// The local watchlist database plus a cached copy of AMFI's NAV file.
public enum WatchlistStore {
    /// `directory == nil` creates an in-memory store (tests).
    public static func container(directory: URL?) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = directory.map { ModelConfiguration(schema: schema, url: $0.appending(path: "Watchlist.store")) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, migrationPlan: FundScopeMigrationPlan.self, configurations: [config])
    }

    public static func defaultDirectory() throws -> URL {
        let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "FundScope", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Deletes the database from the earlier import-based version, which could hold personal amounts.
    public static func removeLegacyStore(in directory: URL) {
        for suffix in ["", "-shm", "-wal"] {
            try? FileManager.default.removeItem(at: directory.appending(path: "FundScope.store\(suffix)"))
        }
    }

    // MARK: Watchlist

    public static func items(_ context: ModelContext) throws -> [WatchlistItem] {
        try context.fetch(FetchDescriptor<WatchlistItem>(sortBy: [SortDescriptor(\.addedAt), SortDescriptor(\.name)]))
    }

    /// Adds schemes that aren't already watched and records their latest NAV. Returns how many were added.
    @discardableResult
    public static func add(_ schemes: [SchemeRecord], now: Date, context: ModelContext) throws -> Int {
        let existing = Set(try items(context).map(\.code))
        var added = 0
        for (offset, scheme) in schemes.enumerated() where !existing.contains(scheme.code) {
            // Offsets keep the order the user added them in.
            context.insert(WatchlistItem(code: scheme.code, name: scheme.name, addedAt: now.addingTimeInterval(Double(offset) / 1000)))
            added += 1
        }
        try recordNAVs(schemes, now: now, context: context)
        try context.save()
        return added
    }

    public static func remove(code: String, context: ModelContext) throws {
        try context.delete(model: WatchlistItem.self, where: #Predicate { $0.code == code })
        try context.delete(model: StoredNAV.self, where: #Predicate { $0.code == code })
        try context.save()
    }

    /// Saves each scheme's published NAV for its date. Existing rows for that date are left as they are.
    public static func recordNAVs(_ schemes: [SchemeRecord], now: Date, context: ModelContext) throws {
        for s in schemes {
            guard let nav = s.nav, let date = s.date else { continue }
            let key = StoredNAV.key(code: s.code, date: date)
            if try context.fetchCount(FetchDescriptor<StoredNAV>(predicate: #Predicate { $0.key == key })) == 0 {
                context.insert(StoredNAV(code: s.code, date: date, nav: nav, retrievedAt: now))
            }
        }
    }

    /// Saves NAV history for one fund. Dates already stored are left untouched. Returns how many were added.
    @discardableResult
    public static func recordHistory(code: String, points: [NAVPoint], now: Date, context: ModelContext) throws -> Int {
        let existing = Set(try context.fetch(FetchDescriptor<StoredNAV>(predicate: #Predicate { $0.code == code })).map(\.key))
        var added = 0
        for p in points where !existing.contains(StoredNAV.key(code: code, date: p.date)) {
            context.insert(StoredNAV(code: code, date: p.date, nav: p.nav, retrievedAt: now))
            added += 1
        }
        try context.save()
        return added
    }

    /// Oldest and newest stored NAV date for a fund.
    public static func historySpan(code: String, context: ModelContext) throws -> (earliest: Date, latest: Date)? {
        var first = FetchDescriptor<StoredNAV>(predicate: #Predicate { $0.code == code }, sortBy: [SortDescriptor(\.date)])
        first.fetchLimit = 1
        var last = FetchDescriptor<StoredNAV>(predicate: #Predicate { $0.code == code }, sortBy: [SortDescriptor(\.date, order: .reverse)])
        last.fetchLimit = 1
        guard let e = try context.fetch(first).first?.date, let l = try context.fetch(last).first?.date else { return nil }
        return (e, l)
    }

    // MARK: AMFI cache

    public static func cachedAMFI(in directory: URL) -> (text: String, fetchedAt: Date)? {
        let url = directory.appending(path: "NAVAll.txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8),
              let date = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)))?[.modificationDate] as? Date else { return nil }
        return (text, date)
    }

    public static func cacheAMFI(_ text: String, in directory: URL) throws {
        try text.write(to: directory.appending(path: "NAVAll.txt"), atomically: true, encoding: .utf8)
    }

    // MARK: Read model

    /// Live prices from Kite, plus the samples taken today for the intraday chart.
    public struct MarketSnapshot: Sendable {
        public var quotes: [String: Quote]
        public var sampleTimes: [Date]
        public var samplePrices: [String: [Decimal]]
        public var health: DataSourceHealth?

        public init(quotes: [String: Quote] = [:], sampleTimes: [Date] = [], samplePrices: [String: [Decimal]] = [:], health: DataSourceHealth? = nil) {
            self.quotes = quotes
            self.sampleTimes = sampleTimes
            self.samplePrices = samplePrices
            self.health = health
        }
    }

    public struct AMFIStatus: Sendable {
        public let fetchedAt: Date?
        public let error: String?
        public let schemeCount: Int

        public init(fetchedAt: Date?, error: String?, schemeCount: Int) {
            self.fetchedAt = fetchedAt
            self.error = error
            self.schemeCount = schemeCount
        }
    }

    /// Builds the dataset the screens use: watched funds, their stored official NAVs and source health.
    public static func dataset(_ context: ModelContext, directory: [String: SchemeRecord], amfi: AMFIStatus,
                               disclosures: [String: [Disclosure]] = [:],
                               market: MarketSnapshot = .init(),
                               frozen: [FrozenEstimate] = [],
                               now: Date, calendar: MarketCalendar = MarketCalendar()) throws -> Dataset {
        let items = try items(context)
        let navs = try context.fetch(FetchDescriptor<StoredNAV>(sortBy: [SortDescriptor(\.date)]))
        let navHistory = Dictionary(grouping: navs, by: \.code).mapValues { $0.map { NAVPoint(date: $0.date, nav: $0.nav) } }
        let funds = items.map { item in
            directory[item.code]?.fundInfo
                ?? FundInfo(code: item.code, name: item.name, amc: "—", category: "—", plan: .direct, isEstimable: false)
        }
        let latest = navs.map(\.date).max()
        let watchedCodes = Set(items.map(\.code))
        let watchedDisclosures = disclosures.filter { watchedCodes.contains($0.key) }
        let latestDisclosures = watchedDisclosures.values.compactMap(\.last)
        let securities = Dictionary(latestDisclosures.flatMap { $0.holdings.compactMap(\.security) }.map { ($0.isin, $0) },
                                    uniquingKeysWith: { a, _ in a }).values.sorted { $0.name < $1.name }
        let missing = items.count - watchedDisclosures.count
        let oldest = latestDisclosures.map(\.disclosureDate).min()
        let amfiState: ProviderStatus = amfi.error != nil ? (amfi.fetchedAt == nil ? .unavailable : .stale)
            : amfi.fetchedAt == nil ? .updating : .connected

        return Dataset(
            isDemo: false, now: now, asOf: market.quotes.values.map(\.exchangeTime).max() ?? now,
            sessionDay: calendar.sessionDay(at: now), sessionIsLive: calendar.status(at: now) == .open, calendar: calendar,
            securities: securities, funds: funds, disclosures: watchedDisclosures, navHistory: navHistory, quotes: market.quotes,
            intradayTimes: market.sampleTimes, intradayPrices: market.samplePrices, benchmarkName: "", benchmarkHistory: [], benchmarkIntraday: [],
            reconciliations: Reconciler.reconcile(frozen.filter { watchedCodes.contains($0.fundCode) }, navHistory: navHistory),
            dataSources: [
                DataSourceHealth(name: "AMFI", detail: "Scheme list and official NAV", status: amfiState,
                                 lastSuccess: amfi.fetchedAt, latestDataDate: latest, records: amfi.schemeCount == 0 ? nil : amfi.schemeCount,
                                 warning: amfi.error.map { amfi.fetchedAt == nil ? $0 : "\($0) Showing the last download." }),
                DataSourceHealth(name: "AMC disclosures", detail: "Monthly fund holdings, imported from fund house files",
                                 status: watchedDisclosures.isEmpty ? .importRequired : (missing > 0 ? .stale : .connected),
                                 lastSuccess: latestDisclosures.compactMap(\.importedAt).max(), latestDataDate: oldest,
                                 records: watchedDisclosures.values.reduce(0) { $0 + $1.count },
                                 warning: missing > 0 ? "\(missing) of \(items.count) watched funds have no holdings imported yet" : nil),
                market.health ?? DataSourceHealth(name: "Zerodha Kite Connect", detail: "Live stock prices only, no account data", status: .authRequired,
                                                  lastSuccess: nil, latestDataDate: nil, records: nil, warning: "Needed for live estimates"),
                DataSourceHealth(name: "Benchmarks", detail: "Index quotes via Kite", status: .unavailable,
                                 lastSuccess: nil, latestDataDate: nil, records: nil, warning: "Needs Kite Connect"),
            ])
    }
}
