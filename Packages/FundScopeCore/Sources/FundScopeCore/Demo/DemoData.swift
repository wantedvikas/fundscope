import Foundation

/// Everything the screens read, in memory. Filled by `DemoData` in demo mode and by `WatchlistStore` + AMFI otherwise.
public struct Dataset: Sendable {
    public let isDemo: Bool
    public let now: Date
    /// Time the live figures are valid for: now during market hours, otherwise the session close.
    public let asOf: Date
    /// The trading day the live/estimated figures belong to.
    public let sessionDay: Date
    public let sessionIsLive: Bool
    public let calendar: MarketCalendar
    public let securities: [SecurityInfo]
    public let funds: [FundInfo]
    /// Oldest first.
    public let disclosures: [String: [Disclosure]]
    public let navHistory: [String: [NAVPoint]]
    public let quotes: [String: Quote]
    /// Intraday quotes per ISIN at each sample time, used to build the intraday estimate chart.
    public let intradayTimes: [Date]
    public let intradayPrices: [String: [Decimal]]
    public let benchmarkName: String
    public let benchmarkHistory: [NAVPoint]
    public let benchmarkIntraday: [NAVPoint]
    public let reconciliations: [Reconciliation]
    public let dataSources: [DataSourceHealth]
}

/// Deterministic, clearly fictional demo data. Company, fund and AMC names are invented so that
/// demo numbers can never be mistaken for real market data. Only used in demo mode.
public enum DemoData {
    public static func make(now: Date = .now, calendar: MarketCalendar = MarketCalendar()) -> Dataset {
        var rng = SplitMix64(seed: 20_261_029)
        let cal = calendar.calendar

        // Session day: today if the market has opened, otherwise the last trading day.
        let status = calendar.status(at: now)
        let sessionDay = calendar.sessionDay(at: now)
        let sessionIsLive = status == .open
        let baselineDay = calendar.previousTradingDay(before: sessionDay)

        let securities = makeSecurities()
        let funds = makeFunds()

        // Official NAV history: ~3 years of trading days ending at the baseline day.
        let start = cal.date(byAdding: .year, value: -3, to: baselineDay)!
        var tradingDays: [Date] = []
        var d = start
        while d <= baselineDay {
            if calendar.isTradingDay(d) { tradingDays.append(d) }
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        var navHistory: [String: [NAVPoint]] = [:]
        let navParams: [String: (start: Double, drift: Double, vol: Double)] = [
            "900101": (48, 0.00055, 0.009), "900102": (62, 0.00045, 0.008), "900103": (31, 0.00070, 0.012),
            "900104": (22, 0.00080, 0.014), "900105": (40, 0.00040, 0.011), "900106": (2950, 0.00027, 0.0002),
        ]
        for fund in funds {
            guard let p = navParams[fund.code] else { continue }
            var nav = p.start
            navHistory[fund.code] = tradingDays.map { day in
                nav *= 1 + p.drift + p.vol * rng.gaussian()
                return NAVPoint(date: day, nav: Decimal(nav).rounded(4))
            }
        }

        // Disclosures for the last two month-ends.
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: sessionDay))!
        let latestDisclosure = cal.date(byAdding: .day, value: -1, to: monthStart)!
        let previousDisclosure = cal.date(byAdding: .day, value: -1, to: cal.date(byAdding: .month, value: -1, to: monthStart)!)!
        var disclosures: [String: [Disclosure]] = [:]
        for fund in funds {
            let old = makeDisclosure(fund: fund, date: previousDisclosure, securities: securities, rng: &rng, previous: nil)
            let new = makeDisclosure(fund: fund, date: latestDisclosure, securities: securities, rng: &rng, previous: old)
            disclosures[fund.code] = [old, new]
        }

        // Quotes: previous close + an intraday path to the latest price (Brownian bridge per stock).
        let open = cal.date(bySettingHour: 9, minute: 15, second: 0, of: sessionDay)!
        let close = cal.date(bySettingHour: 15, minute: 30, second: 0, of: sessionDay)!
        let end = sessionIsLive ? min(now, close) : close
        var times: [Date] = []
        var t = open
        while t <= end { times.append(t); t = t.addingTimeInterval(300) }
        if times.last != end { times.append(end) }
        let progress = end.timeIntervalSince(open) / close.timeIntervalSince(open)

        let market = 0.006 * rng.gaussian() * sqrt(progress)
        var quotes: [String: Quote] = [:]
        var intraday: [String: [Decimal]] = [:]
        for (i, s) in securities.enumerated() {
            let prevClose = 150 + Double(i * 97 % 2400) + rng.next01() * 50
            let finalReturn = market * (0.7 + 0.6 * rng.next01()) + 0.012 * rng.gaussian() * sqrt(progress)
            var walk = 0.0
            var path: [Double] = []
            for _ in times { walk += 0.0015 * rng.gaussian(); path.append(walk) }
            let n = Double(max(times.count - 1, 1))
            let prices = path.enumerated().map { j, w in
                let frac = Double(j) / n
                let bridged = finalReturn * frac + (w - path.last! * frac)
                return Decimal(prevClose * (1 + bridged)).rounded(2)
            }
            intraday[s.isin] = prices
            // One quote is left stale to show how the model treats it.
            let quoteTime = s.symbol == "TUNGA" ? end.addingTimeInterval(-1800) : end
            quotes[s.isin] = Quote(isin: s.isin, price: prices.last!, previousClose: Decimal(prevClose).rounded(2), exchangeTime: quoteTime)
        }

        // Benchmark: fictional price index.
        var level = 18_400.0
        let benchmarkHistory = tradingDays.map { day in
            level *= 1 + 0.0004 + 0.0085 * rng.gaussian()
            return NAVPoint(date: day, nav: Decimal(level).rounded(2))
        }
        let benchmarkIntraday = times.enumerated().map { j, time in
            NAVPoint(date: time, nav: Decimal(level * (1 + market * Double(j) / Double(max(times.count - 1, 1)))).rounded(2))
        }

        // Reconciliation history: last 45 trading days for estimable funds.
        var reconciliations: [Reconciliation] = []
        for fund in funds where fund.isEstimable {
            let history = navHistory[fund.code] ?? []
            let bias = 0.02 * rng.gaussian()
            for point in history.suffix(45) {
                let err = (bias + 0.11 * rng.gaussian()) / 100
                reconciliations.append(Reconciliation(
                    fundCode: fund.code, valuationDate: point.date,
                    estimatedNAV: (point.nav * Decimal(1 + err)).rounded(4), officialNAV: point.nav,
                    coverage: Decimal(92 + 6 * rng.next01()).rounded(1),
                    holdingsDate: point.date > latestDisclosure ? latestDisclosure : previousDisclosure,
                    modelVersion: NAVEstimator.modelVersion))
            }
        }

        let dataSources = [
            DataSourceHealth(name: "Zerodha Kite Connect", detail: "Simulated market data (demo)", status: sessionIsLive ? .connected : .stale,
                             lastSuccess: end, latestDataDate: sessionDay, records: securities.count,
                             warning: sessionIsLive ? nil : "Market closed. Showing the last session."),
            DataSourceHealth(name: "AMFI", detail: "Scheme directory and official NAV", status: .connected,
                             lastSuccess: cal.date(byAdding: .hour, value: -10, to: now), latestDataDate: baselineDay,
                             records: tradingDays.count * funds.count, warning: nil),
            DataSourceHealth(name: "AMC disclosures", detail: "Monthly portfolio files", status: .stale,
                             lastSuccess: cal.date(byAdding: .day, value: 9, to: latestDisclosure), latestDataDate: latestDisclosure,
                             records: disclosures.values.reduce(0) { $0 + $1.count }, warning: "Konkan Small Cap: disclosure for last month not imported yet"),
            DataSourceHealth(name: "Benchmarks", detail: "Index quotes via Kite", status: .connected,
                             lastSuccess: end, latestDataDate: sessionDay, records: benchmarkHistory.count, warning: nil),
        ]

        return Dataset(
            isDemo: true, now: now, asOf: end, sessionDay: sessionDay, sessionIsLive: sessionIsLive, calendar: calendar,
            securities: securities, funds: funds, disclosures: disclosures, navHistory: navHistory,
            quotes: quotes, intradayTimes: times, intradayPrices: intraday,
            benchmarkName: "Demo 50 Index", benchmarkHistory: benchmarkHistory, benchmarkIntraday: benchmarkIntraday,
            reconciliations: reconciliations, dataSources: dataSources)
    }

    static func makeSecurities() -> [SecurityInfo] {
        let rows: [(String, String, String, MarketCap)] = [
            ("Aravali Bank", "ARAVALI", "Banking", .large), ("Deccan Bank", "DECCAN", "Banking", .large),
            ("Malabar Bank", "MALABAR", "Banking", .mid), ("Sindhu Finance", "SINDHU", "Financial Services", .large),
            ("Vindhya Capital", "VINDHYA", "Financial Services", .mid), ("Kaveri Infotech", "KAVERI", "IT", .large),
            ("Nilgiri Systems", "NILGIRI", "IT", .large), ("Satpura Software", "SATPURA", "IT", .mid),
            ("Godavari Pharma", "GODAVARI", "Healthcare", .large), ("Tapti Healthcare", "TAPTI", "Healthcare", .mid),
            ("Chambal Diagnostics", "CHAMBAL", "Healthcare", .small), ("Konark Consumer", "KONARK", "Consumer", .large),
            ("Hampi Foods", "HAMPI", "Consumer", .mid), ("Thar Motors", "THAR", "Automobile", .large),
            ("Sunderban Auto Parts", "SUNDER", "Automobile", .small), ("Lohit Energy", "LOHIT", "Energy", .large),
            ("Brahmaputra Power", "BRAHMA", "Energy", .mid), ("Mahanadi Engineering", "MAHANADI", "Capital Goods", .large),
            ("Tunga Industries", "TUNGA", "Capital Goods", .small), ("Ajanta Exchange", "AJANTA", "Capital Markets", .mid),
            ("Ellora Depository", "ELLORA", "Capital Markets", .small), ("Palk Telecom", "PALK", "Telecom", .large),
            ("Kutch Metals", "KUTCH", "Metals", .mid), ("Shivalik Chemicals", "SHIVALIK", "Chemicals", .small),
            ("Pench Cements", "PENCH", "Materials", .mid), ("Kosi Realty", "KOSI", "Real Estate", .small),
            ("Sabari Logistics", "SABARI", "Services", .small), ("Periyar Insurance", "PERIYAR", "Financial Services", .large),
        ]
        return rows.enumerated().map { i, r in
            SecurityInfo(isin: String(format: "DEMO%08d", i + 1), name: r.0, symbol: r.1, sector: r.2, marketCap: r.3)
        }
    }

    static func makeFunds() -> [FundInfo] {
        [
            FundInfo(code: "900101", name: "Meridian Flexi Cap Fund", amc: "Meridian Mutual Fund", category: "Flexi Cap", plan: .direct, isEstimable: true),
            FundInfo(code: "900102", name: "Sahyadri Large Cap Fund", amc: "Sahyadri Mutual Fund", category: "Large Cap", plan: .direct, isEstimable: true),
            FundInfo(code: "900103", name: "Indus Midcap Opportunities Fund", amc: "Indus Mutual Fund", category: "Mid Cap", plan: .direct, isEstimable: true),
            FundInfo(code: "900104", name: "Konkan Small Cap Fund", amc: "Konkan Mutual Fund", category: "Small Cap", plan: .direct, isEstimable: true),
            FundInfo(code: "900105", name: "Ganga Banking & Financial Services Fund", amc: "Sahyadri Mutual Fund", category: "Sectoral", plan: .direct, isEstimable: true),
            FundInfo(code: "900106", name: "Narmada Liquid Fund", amc: "Meridian Mutual Fund", category: "Liquid", plan: .direct, isEstimable: false),
        ]
    }

    static func makeDisclosure(fund: FundInfo, date: Date, securities: [SecurityInfo], rng: inout SplitMix64, previous: Disclosure?) -> Disclosure {
        if fund.category == "Liquid" {
            return Disclosure(fundCode: fund.code, disclosureDate: date, holdings: [
                DisclosedHolding(rawName: "91 Day Treasury Bill", security: nil, assetType: .debt, weight: 38.4, quantity: nil),
                DisclosedHolding(rawName: "Certificate of Deposit — Demo Bank", security: nil, assetType: .debt, weight: 31.2, quantity: nil),
                DisclosedHolding(rawName: "Commercial Paper — Demo NBFC", security: nil, assetType: .debt, weight: 22.9, quantity: nil),
                DisclosedHolding(rawName: "TREPS", security: nil, assetType: .cash, weight: 7.5, quantity: nil),
            ])
        }
        let pool: [SecurityInfo] = securities.filter { s in
            switch fund.category {
            case "Large Cap": s.marketCap == .large
            case "Mid Cap": s.marketCap == .mid || (s.marketCap == .large && s.sector != "Banking")
            case "Small Cap": s.marketCap == .small || s.marketCap == .mid
            case "Sectoral": s.sector == "Banking" || s.sector == "Financial Services" || s.sector == "Capital Markets"
            default: true
            }
        }
        var chosen: [SecurityInfo]
        if let previous {
            let held = previous.holdings.compactMap(\.security)
            chosen = Array(held.dropLast())
            if let extra = pool.first(where: { s in !held.contains(s) }) { chosen.append(extra) }
        } else {
            chosen = Array(pool.prefix(min(pool.count, 18)))
        }
        let cash = 3.0 + 3 * rng.next01()
        let foreign = fund.category == "Flexi Cap" ? 4.5 : 0
        let raw = chosen.enumerated().map { i, _ in 1.0 / Double(i + 2).squareRoot() + 0.15 * rng.next01() }
        let scale = (100 - cash - foreign) / raw.reduce(0, +)
        let tracksQuantity = fund.category != "Sectoral"
        var holdings = zip(chosen, raw).map { s, w in
            let weight = Decimal(w * scale).rounded(2)
            let previousQty = previous?.holdings.first { $0.security == s }?.quantity
            let qty: Decimal? = tracksQuantity ? (previousQty.map { ($0 * Decimal(0.9 + 0.25 * rng.next01())).rounded(0) } ?? (weight * 10_000).rounded(0)) : nil
            return DisclosedHolding(rawName: s.name, security: s, assetType: .equity, weight: weight, quantity: qty)
        }
        if foreign > 0 {
            holdings.append(DisclosedHolding(rawName: "Demo Global Tech Inc (ADR)", security: nil, assetType: .foreignEquity, weight: Decimal(foreign).rounded(2), quantity: nil))
        }
        holdings.append(DisclosedHolding(rawName: "TREPS / Net receivables", security: nil, assetType: .cash, weight: Decimal(cash).rounded(2), quantity: nil))
        return Disclosure(fundCode: fund.code, disclosureDate: date, holdings: holdings.sorted { $0.weight > $1.weight })
    }
}

/// Small seeded RNG so demo data is identical on every launch.
struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func next01() -> Double { Double(next() >> 11) / Double(1 << 53) }

    mutating func gaussian() -> Double {
        let u1 = max(next01(), .leastNonzeroMagnitude), u2 = next01()
        return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
    }
}
