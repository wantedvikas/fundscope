import Foundation

/// The estimate saved at the end of a trading day. Never changed afterwards, so accuracy is judged on what was actually shown.
public struct FrozenEstimate: Hashable, Sendable, Codable {
    public let fundCode: String
    /// Trading day the estimate is for (the official NAV for this day is what it's compared with).
    public let valuationDate: Date
    public let estimatedNAV: Decimal
    public let baselineNAV: Decimal
    public let coverage: Decimal
    public let holdingsDate: Date
    public let modelVersion: String
    /// Newest quote time used, and when the estimate was saved.
    public let quoteTime: Date
    public let frozenAt: Date

    public init(fundCode: String, valuationDate: Date, estimatedNAV: Decimal, baselineNAV: Decimal, coverage: Decimal,
                holdingsDate: Date, modelVersion: String, quoteTime: Date, frozenAt: Date) {
        self.fundCode = fundCode
        self.valuationDate = valuationDate
        self.estimatedNAV = estimatedNAV
        self.baselineNAV = baselineNAV
        self.coverage = coverage
        self.holdingsDate = holdingsDate
        self.modelVersion = modelVersion
        self.quoteTime = quoteTime
        self.frozenAt = frozenAt
    }
}

/// Freezing end-of-day estimates and comparing them with official NAVs (docs/10-nav-engine.md §2–3).
public enum Reconciler {
    /// Freeze once a trading day's session has closed and the quotes used were taken at or after 15:25 IST that day,
    /// so the estimate reflects (near-)closing prices rather than an intraday moment.
    public static func shouldFreeze(now: Date, latestQuoteTime: Date?, alreadyFrozenToday: Bool, calendar: MarketCalendar) -> Bool {
        guard !alreadyFrozenToday, calendar.isTradingDay(now), calendar.status(at: now) == .closed,
              calendar.calendar.component(.hour, from: now) >= 15, let quoteTime = latestQuoteTime,
              calendar.calendar.isDate(quoteTime, inSameDayAs: now) else { return false }
        let c = calendar.calendar.dateComponents([.hour, .minute], from: quoteTime)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0) >= 15 * 60 + 25
    }

    /// Final estimates from today's data, for funds the model could estimate.
    public static func freeze(_ data: Dataset, now: Date) -> [FrozenEstimate] {
        Analytics.watched(data).compactMap { w in
            guard let e = w.estimate, let nav = e.estimatedNAV, let holdingsDate = w.holdingsDate else { return nil }
            return FrozenEstimate(fundCode: w.fund.code, valuationDate: data.sessionDay, estimatedNAV: nav, baselineNAV: e.baselineNAV,
                                  coverage: e.coverage.rounded(2), holdingsDate: holdingsDate, modelVersion: e.modelVersion,
                                  quoteTime: data.asOf, frozenAt: now)
        }
    }

    /// Pairs each frozen estimate with the official NAV for the same fund and day. Estimates still waiting for their NAV are left out.
    public static func reconcile(_ frozen: [FrozenEstimate], navHistory: [String: [NAVPoint]]) -> [Reconciliation] {
        frozen.compactMap { f in
            guard let official = navHistory[f.fundCode]?.first(where: { $0.date == f.valuationDate }) else { return nil }
            return Reconciliation(fundCode: f.fundCode, valuationDate: f.valuationDate, estimatedNAV: f.estimatedNAV,
                                  officialNAV: official.nav, coverage: f.coverage, holdingsDate: f.holdingsDate, modelVersion: f.modelVersion)
        }
        .sorted { $0.valuationDate < $1.valuationDate }
    }
}
