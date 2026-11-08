import Foundation
import Testing
@testable import FundScopeCore

@Suite struct NAVEstimatorTests {
    let now = ist(2026, 10, 27, 11, 0)

    func quote(_ id: String, _ prev: Decimal, _ price: Decimal, age: TimeInterval = 10) -> (String, Quote) {
        (id, Quote(isin: id, price: price, previousClose: prev, exchangeTime: now.addingTimeInterval(-age)))
    }

    // A 50% +2%, B 30% −1.5%, C 15% +2%, cash 5% → 1.00 − 0.45 + 0.30 = 0.85 pp → NAV 100.85
    @Test func handComputedThreeStockFund() {
        let holdings = [equity("A", 50), equity("B", 30), equity("C", 15), other("Cash", .cash, 5)]
        let quotes = Dictionary(uniqueKeysWithValues: [quote("A", 100, 102), quote("B", 200, 197), quote("C", 50, 51)])
        let e = NAVEstimator.estimate(holdings: holdings, quotes: quotes, baselineNAV: 100, now: now)
        #expect(e.estimatedNAV == Decimal(string: "100.85"))
        #expect(e.estimatedReturn == Decimal(string: "0.85"))
        #expect(e.coverage == 100)
        #expect(e.status == .ok)
        #expect(e.contributions.first?.holding.id == "A")
    }

    // C unpriced: priced 0.55 pp over 80% → avg 0.006875; C assumed 15 × 0.006875 = 0.103125 → 0.653125 pp
    @Test func unpricedEquityMovesWithPricedAverage() {
        let holdings = [equity("A", 50), equity("B", 30), equity("C", 15), other("Cash", .cash, 5)]
        let quotes = Dictionary(uniqueKeysWithValues: [quote("A", 100, 102), quote("B", 200, 197)])
        let e = NAVEstimator.estimate(holdings: holdings, quotes: quotes, baselineNAV: 100, now: now)
        #expect(e.estimatedNAV == Decimal(string: "100.653125"))
        #expect(e.unpricedWeight == 15)
        #expect(e.coverage == 85)
        #expect(e.status == .lowCoverage)
    }

    @Test func staleQuoteCountsAsUnpriced() {
        let holdings = [equity("A", 95), other("Cash", .cash, 5)]
        let e = NAVEstimator.estimate(holdings: holdings, quotes: Dictionary(uniqueKeysWithValues: [quote("A", 100, 101, age: 600)]),
                                      baselineNAV: 100, now: now)
        #expect(e.status == .notEstimable("No live prices for disclosed equity holdings"))
        #expect(e.estimatedNAV == nil)
        #expect(e.contributions.first?.isStale == true)
    }

    @Test func tooMuchUnsupportedIsNotEstimable() {
        let holdings = [equity("A", 85), other("Futures", .derivative, 12), other("Cash", .cash, 3)]
        let e = NAVEstimator.estimate(holdings: holdings, quotes: Dictionary(uniqueKeysWithValues: [quote("A", 100, 101)]),
                                      baselineNAV: 100, now: now)
        guard case .notEstimable = e.status else { Issue.record("expected notEstimable"); return }
        #expect(e.estimatedNAV == nil)
    }

    @Test func etfIsPricedAndLiquidFundIsFlat() {
        let gold = DisclosedHolding(rawName: "ICICI Prudential Gold ETF", security: security("GOLDETF"), assetType: .fundUnits, weight: 20, quantity: nil)
        let liquid = DisclosedHolding(rawName: "Invesco India Liquid Fund - Direct Plan", security: nil, assetType: .fundUnits, weight: 20, quantity: nil)
        let e = NAVEstimator.estimate(holdings: [equity("A", 60), gold, liquid],
                                      quotes: Dictionary(uniqueKeysWithValues: [quote("A", 100, 101), quote("GOLDETF", 100, 102)]),
                                      baselineNAV: 100, now: now)
        #expect(e.status == .ok)
        #expect(e.flatWeight == 20 && e.unsupportedWeight == 0)
        #expect(e.estimatedNAV == Decimal(string: "101.0"))  // 60% × 1% + 20% × 2%
    }

    @Test func arbitrageFundIsFlatEstimate() {
        let e = NAVEstimator.estimate(holdings: [other("Reliance", .hedged, 70), other("TREPS", .cash, 30)], quotes: [:], baselineNAV: 37, now: now)
        #expect(e.status == .ok)
        #expect(e.estimatedNAV == 37)
    }

    @Test func allDebtFundIsNotEstimable() {
        let e = NAVEstimator.estimate(holdings: [other("T-Bill", .debt, 90), other("TREPS", .cash, 10)], quotes: [:], baselineNAV: 1000, now: now)
        guard case .notEstimable = e.status else { Issue.record("expected notEstimable"); return }
    }
}

@Suite struct LookThroughTests {
    let a = Disclosure(fundCode: "A", disclosureDate: ist(2026, 9, 30), holdings: [equity("X", 40), equity("Y", 30), other("Cash", .cash, 30)])
    let b = Disclosure(fundCode: "B", disclosureDate: ist(2026, 9, 30), holdings: [equity("X", 20), equity("Z", 50), equity("Y", 10), other("Cash", .cash, 20)])

    @Test func overlapIsSumOfMinWeights() {
        #expect(LookThrough.overlap(a, b) == 30)
        #expect(LookThrough.overlap(b, a) == 30)
    }

    @Test func exposureAddsUpAndKeepsNonEquitySeparate() {
        let rows = LookThrough.exposure(positions: [(1000, a), (2000, b)]) { ($0.isin, $0.name) }
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        #expect(byID["X"]?.value == 800)
        #expect(byID["Y"]?.value == 500)
        #expect(byID["Z"]?.value == 1000)
        #expect(byID[LookThrough.nonEquityKey]?.value == 700)
        #expect(abs(rows.reduce(Decimal(0)) { $0 + $1.share } - 100) < Decimal(string: "0.000001")!)
        #expect(byID["X"]?.fundCodes == ["A", "B"])
    }

    @Test func weightGapBecomesUnmapped() {
        let short = Disclosure(fundCode: "S", disclosureDate: ist(2026, 9, 30), holdings: [equity("X", 97)])
        let rows = LookThrough.exposure(positions: [(100, short)]) { ($0.isin, $0.name) }
        #expect(rows.first { $0.id == LookThrough.unmappedKey }?.value == 3)
    }
}

@Suite struct DisclosureDiffTests {
    @Test func classifiesChanges() {
        let old = Disclosure(fundCode: "F", disclosureDate: ist(2026, 8, 31), holdings: [equity("X", 10, qty: 100), equity("Y", 5, qty: 50)])
        let new = Disclosure(fundCode: "F", disclosureDate: ist(2026, 9, 30), holdings: [equity("X", 12, qty: 200), equity("Z", 3, qty: 10)])
        let changes = Dictionary(uniqueKeysWithValues: DisclosureDiff.compare(old: old, new: new).map { ($0.key, $0) })
        #expect(changes["X"]?.kind == .increased)
        #expect(changes["X"]?.isQuantityConfirmed == true)
        #expect(changes["X"]?.possibleCorporateAction == true)
        #expect(changes["Y"]?.kind == .exited)
        #expect(changes["Z"]?.kind == .new)
    }

    @Test func weightOnlyChangeIsNotConfirmed() {
        let old = Disclosure(fundCode: "F", disclosureDate: ist(2026, 8, 31), holdings: [equity("X", 10)])
        let new = Disclosure(fundCode: "F", disclosureDate: ist(2026, 9, 30), holdings: [equity("X", 8)])
        let change = DisclosureDiff.compare(old: old, new: new).first
        #expect(change?.kind == .decreased)
        #expect(change?.isQuantityConfirmed == false)
    }
}

@Suite struct AccuracyStatsTests {
    @Test func statsFromKnownErrors() throws {
        let day = ist(2026, 10, 1)
        let rows = [Decimal(string: "100.1")!, Decimal(string: "99.7")!, Decimal(string: "100.2")!].enumerated().map { i, est in
            Reconciliation(fundCode: "F", valuationDate: day.addingTimeInterval(Double(i) * 86_400), estimatedNAV: est,
                           officialNAV: 100, coverage: 95, holdingsDate: day, modelVersion: "t")
        }
        let s = AccuracyStats(rows)
        #expect(s.count == 3)
        #expect(s.medianAbsError == Decimal(string: "0.2"))
        #expect(s.worstError == Decimal(string: "-0.3"))
        #expect(abs(try #require(s.meanAbsError) - Decimal(string: "0.2")!) < Decimal(string: "0.0001")!)
        #expect(s.hasEnoughHistory == false)
    }

    @Test func emptyIsUnknownNotZero() {
        let s = AccuracyStats([])
        #expect(s.meanAbsError == nil)
        #expect(s.worstError == nil)
    }
}
