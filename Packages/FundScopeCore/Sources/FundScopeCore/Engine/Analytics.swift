import Foundation

/// One watched fund with official and estimated figures kept apart. No personal amounts.
public struct WatchedFund: Identifiable, Hashable, Sendable {
    public var id: String { fund.code }
    public let fund: FundInfo
    /// Latest official NAV and the one before it.
    public let official: NAVPoint?
    public let previousOfficial: NAVPoint?
    public let estimate: NAVEstimator.Estimate?
    public let holdingsDate: Date?

    /// Change between the last two official NAVs, in percent.
    public var officialChange: Decimal? {
        guard let o = official, let p = previousOfficial, p.nav > 0 else { return nil }
        return (o.nav / p.nav - 1) * 100
    }
}

/// Builds screen-ready figures from a `Dataset` using the engine.
public enum Analytics {
    public static func latestDisclosure(_ data: Dataset, fund: String) -> Disclosure? {
        data.disclosures[fund]?.last
    }

    public static func estimate(_ data: Dataset, fund: FundInfo) -> NAVEstimator.Estimate? {
        // No market data provider yet means no estimate, rather than an estimate that looks broken.
        guard !data.quotes.isEmpty, let baseline = data.navHistory[fund.code]?.last, let disclosure = latestDisclosure(data, fund: fund.code) else { return nil }
        // A thinly traded stock's last trade earlier today is still its price; only a quote from before today's open
        // (no trade this session) counts as unpriced. Fetch staleness is tracked separately as provider health.
        let sessionOpen = data.calendar.calendar.date(bySettingHour: 9, minute: 15, second: 0, of: data.sessionDay) ?? data.sessionDay
        let e = NAVEstimator.estimate(holdings: disclosure.holdings, quotes: data.quotes, baselineNAV: baseline.nav, now: data.asOf,
                                      staleAfter: max(300, data.asOf.timeIntervalSince(sessionOpen)))
        // Kite's previous close is for the trading day before the session; the official NAV must be for that same day.
        let expectedBaseline = data.calendar.previousTradingDay(before: data.sessionDay)
        guard baseline.date == expectedBaseline else {
            return NAVEstimator.Estimate(estimatedNAV: nil, estimatedReturn: nil, baselineNAV: baseline.nav,
                                         pricedWeight: e.pricedWeight, unpricedWeight: e.unpricedWeight, flatWeight: e.flatWeight,
                                         unsupportedWeight: e.unsupportedWeight, contributions: e.contributions,
                                         status: .notEstimable("Official NAV for \(FinanceFormat.date(expectedBaseline)) isn't published yet"),
                                         modelVersion: e.modelVersion)
        }
        guard fund.isEstimable else {
            return NAVEstimator.Estimate(estimatedNAV: nil, estimatedReturn: nil, baselineNAV: baseline.nav,
                                         pricedWeight: e.pricedWeight, unpricedWeight: e.unpricedWeight, flatWeight: e.flatWeight,
                                         unsupportedWeight: e.unsupportedWeight, contributions: e.contributions,
                                         status: .notEstimable("\(fund.category) funds are not estimated"), modelVersion: e.modelVersion)
        }
        return e
    }

    public static func watched(_ data: Dataset) -> [WatchedFund] {
        data.funds.map { fund in
            let history = data.navHistory[fund.code] ?? []
            return WatchedFund(fund: fund, official: history.last, previousOfficial: history.dropLast().last,
                               estimate: estimate(data, fund: fund),
                               holdingsDate: latestDisclosure(data, fund: fund.code)?.disclosureDate)
        }
    }

    /// Return from the last NAV on or before `start` to the latest NAV, in percent. Nil without enough history.
    public static func trailingReturn(_ history: [NAVPoint], from start: Date) -> Decimal? {
        guard let last = history.last, let first = history.last(where: { $0.date <= start }), first.nav > 0 else { return nil }
        return (last.nav / first.nav - 1) * 100
    }

    /// Equal-weight average of the funds that have an estimate. Nil when none do.
    public static func averageEstimatedChange(_ funds: [WatchedFund]) -> Decimal? {
        let changes = funds.compactMap { $0.estimate?.estimatedReturn }
        return changes.isEmpty ? nil : changes.reduce(0, +) / Decimal(changes.count)
    }

    /// Equal-weight average of the latest official one-day changes. Nil when none are known.
    public static func averageOfficialChange(_ funds: [WatchedFund]) -> Decimal? {
        let changes = funds.compactMap(\.officialChange)
        return changes.isEmpty ? nil : changes.reduce(0, +) / Decimal(changes.count)
    }

    /// Combined look-through exposure with every watched fund weighted equally.
    public static func exposures(_ data: Dataset, key: (SecurityInfo) -> (id: String, name: String)) -> [LookThrough.Exposure] {
        let positions: [(value: Decimal, disclosure: Disclosure)] = data.funds.compactMap { fund in
            latestDisclosure(data, fund: fund.code).map { (1, $0) }
        }
        return LookThrough.exposure(positions: positions, key: key)
    }

    /// Estimated NAV through the session, one point per sample time.
    public static func intradayEstimate(_ data: Dataset, fund: FundInfo) -> [NAVPoint] {
        guard fund.isEstimable, let baseline = data.navHistory[fund.code]?.last,
              let disclosure = latestDisclosure(data, fund: fund.code) else { return [] }
        return data.intradayTimes.enumerated().compactMap { j, time in
            var quotes: [String: Quote] = [:]
            for (isin, prices) in data.intradayPrices where j < prices.count {
                guard let prev = data.quotes[isin]?.previousClose else { continue }
                quotes[isin] = Quote(isin: isin, price: prices[j], previousClose: prev, exchangeTime: time)
            }
            let e = NAVEstimator.estimate(holdings: disclosure.holdings, quotes: quotes, baselineNAV: baseline.nav, now: time)
            return e.estimatedNAV.map { NAVPoint(date: time, nav: $0) }
        }
    }
}
