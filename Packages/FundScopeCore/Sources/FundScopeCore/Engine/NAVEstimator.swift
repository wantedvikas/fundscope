import Foundation

/// Estimated intraday NAV, model v1 (docs/10-nav-engine.md §1).
public enum NAVEstimator {
    public static let modelVersion = "v1.1-flat-residual"

    public struct Contribution: Identifiable, Hashable, Sendable {
        public var id: String { holding.id }
        public let holding: DisclosedHolding
        public let quote: Quote?
        /// Contribution to fund return in percent points (weight% × stock return).
        public let contribution: Decimal?
        public let isStale: Bool
    }

    public enum Status: Hashable, Sendable {
        case ok
        case lowCoverage
        case notEstimable(String)
    }

    public struct Estimate: Hashable, Sendable {
        public let estimatedNAV: Decimal?
        /// Estimated fund return in percent.
        public let estimatedReturn: Decimal?
        public let baselineNAV: Decimal
        /// Weight percentages; together they sum to the disclosure total.
        public let pricedWeight: Decimal
        public let unpricedWeight: Decimal
        public let flatWeight: Decimal
        public let unsupportedWeight: Decimal
        public let contributions: [Contribution]
        public let status: Status
        public let modelVersion: String

        public var coverage: Decimal {
            let total = pricedWeight + unpricedWeight + flatWeight + unsupportedWeight
            return total == 0 ? 0 : (pricedWeight + flatWeight) / total * 100
        }
    }

    /// - Parameters:
    ///   - quotes: latest quotes keyed by ISIN; `previousClose` must belong to the same day as `baselineNAV`.
    ///   - staleAfter: a quote older than this (relative to `now`) counts as unpriced.
    public static func estimate(
        holdings: [DisclosedHolding],
        quotes: [String: Quote],
        baselineNAV: Decimal,
        now: Date,
        staleAfter: TimeInterval = 300
    ) -> Estimate {
        var priced: Decimal = 0, unpriced: Decimal = 0, flat: Decimal = 0, unsupported: Decimal = 0
        var pricedReturnSum: Decimal = 0
        var contributions: [Contribution] = []

        for holding in holdings {
            if holding.assetType.isFlatResidual || (holding.assetType == .fundUnits && isCashFund(holding.rawName)) {
                flat += holding.weight
                continue
            }
            // Anything listed on the NSE (stocks, ETFs) is priced the same way; only stocks count as unpriced when missing.
            let quote = holding.security.flatMap { quotes[$0.isin] }
            let stale = quote.map { now.timeIntervalSince($0.exchangeTime) > staleAfter } ?? true
            if let quote, !stale, quote.previousClose > 0 {
                let c = holding.weight * (quote.price / quote.previousClose - 1)
                priced += holding.weight
                pricedReturnSum += c
                contributions.append(.init(holding: holding, quote: quote, contribution: c, isStale: false))
            } else if holding.assetType == .equity {
                unpriced += holding.weight
                contributions.append(.init(holding: holding, quote: quote, contribution: nil, isStale: quote != nil))
            } else {
                unsupported += holding.weight
            }
        }

        let total = priced + unpriced + flat + unsupported
        let coverage = total == 0 ? 0 : (priced + flat) / total * 100
        let unsupportedShare = total == 0 ? 0 : unsupported / total * 100

        let status: Status
        // An arbitrage fund (hedged pairs plus cash) is a flat estimate; a fund with nothing priced and no hedges isn't.
        if priced == 0, unpriced > 0 || !holdings.contains(where: { $0.assetType == .hedged }) {
            status = .notEstimable("No live prices for disclosed equity holdings")
        } else if unsupportedShare > 10 {
            status = .notEstimable("\(FinanceFormat.percent(unsupportedShare, signed: false)) of the fund is in assets the model can't price")
        } else if coverage < 75 {
            status = .notEstimable("Only \(FinanceFormat.percent(coverage, signed: false)) of the fund has live prices")
        } else if coverage < 90 {
            status = .lowCoverage
        } else {
            status = .ok
        }

        var fundReturn: Decimal?
        var nav: Decimal?
        if case .notEstimable = status {} else {
            // Unpriced equity is assumed to move with the priced-equity average (stated model assumption).
            let pricedAverage = priced == 0 ? 0 : pricedReturnSum / priced
            let r = (pricedReturnSum + unpriced * pricedAverage) / 100
            fundReturn = r * 100
            nav = baselineNAV * (1 + r)
        }

        return Estimate(
            estimatedNAV: nav,
            estimatedReturn: fundReturn,
            baselineNAV: baselineNAV,
            pricedWeight: priced,
            unpricedWeight: unpriced,
            flatWeight: flat,
            unsupportedWeight: unsupported,
            contributions: contributions.sorted { ($0.contribution ?? 0) > ($1.contribution ?? 0) },
            status: status,
            modelVersion: modelVersion
        )
    }

    /// Liquid, money-market and overnight fund units move a few basis points a day, like the cash they hold.
    static func isCashFund(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("liquid") || n.contains("money market") || n.contains("overnight")
    }
}
