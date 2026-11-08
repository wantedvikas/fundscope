import Foundation
import Testing
@testable import FundScopeCore

@Suite struct ReconcilerTests {
    let calendar = MarketCalendar()

    @Test func freezesOnlyAfterCloseWithClosingQuotes() {
        let close = ist(2026, 10, 29, 15, 40)
        #expect(Reconciler.shouldFreeze(now: close, latestQuoteTime: ist(2026, 10, 29, 15, 29), alreadyFrozenToday: false, calendar: calendar))
        // Market still open.
        #expect(!Reconciler.shouldFreeze(now: ist(2026, 10, 29, 15, 0), latestQuoteTime: ist(2026, 10, 29, 14, 59), alreadyFrozenToday: false, calendar: calendar))
        // Quotes only from the morning (app slept through the afternoon): not a closing estimate.
        #expect(!Reconciler.shouldFreeze(now: close, latestQuoteTime: ist(2026, 10, 29, 11, 0), alreadyFrozenToday: false, calendar: calendar))
        // Yesterday's quotes, a weekend, or already done.
        #expect(!Reconciler.shouldFreeze(now: close, latestQuoteTime: ist(2026, 10, 28, 15, 29), alreadyFrozenToday: false, calendar: calendar))
        #expect(!Reconciler.shouldFreeze(now: ist(2026, 10, 31, 16), latestQuoteTime: ist(2026, 10, 31, 15, 29), alreadyFrozenToday: false, calendar: calendar))
        #expect(!Reconciler.shouldFreeze(now: close, latestQuoteTime: ist(2026, 10, 29, 15, 29), alreadyFrozenToday: true, calendar: calendar))
    }

    func frozen(_ code: String, _ day: Date, _ nav: Decimal) -> FrozenEstimate {
        FrozenEstimate(fundCode: code, valuationDate: day, estimatedNAV: nav, baselineNAV: 100, coverage: 95, holdingsDate: ist(2026, 9, 30),
                       modelVersion: "v1", quoteTime: day, frozenAt: day)
    }

    @Test func reconcilesOnlyMatchingDays() {
        let navs = ["A": [NAVPoint(date: ist(2026, 10, 28), nav: 100), NAVPoint(date: ist(2026, 10, 29), nav: 101)]]
        let rows = Reconciler.reconcile([frozen("A", ist(2026, 10, 29), Decimal(string: "101.202")!),
                                         frozen("A", ist(2026, 10, 30), 102), // official NAV not out yet
                                         frozen("B", ist(2026, 10, 29), 50)], navHistory: navs)
        #expect(rows.count == 1)
        #expect(rows[0].officialNAV == 101)
        #expect(rows[0].pctError == Decimal(string: "0.2"))
    }

    @Test func demoEstimatesFreezeWithTheirInputs() {
        let data = DemoData.make(now: ist(2026, 10, 29, 15, 40))
        let estimates = Reconciler.freeze(data, now: data.now)
        #expect(!estimates.isEmpty)
        #expect(estimates.allSatisfy { $0.valuationDate == ist(2026, 10, 29) && $0.modelVersion == NAVEstimator.modelVersion })
        #expect(!estimates.contains { $0.fundCode == "900106" }) // the liquid fund is never estimated
    }

    @Test func storeWritesEachDayOnce() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let day = ist(2026, 10, 29)
        #expect(try EstimateStore.save([frozen("A", day, 101)], day: day, in: dir))
        #expect(try !EstimateStore.save([frozen("A", day, 999)], day: day, in: dir)) // a later run can't change it
        #expect(try !EstimateStore.save([], day: ist(2026, 10, 30), in: dir))
        #expect(EstimateStore.load(in: dir) == [frozen("A", day, 101)])
    }
}
