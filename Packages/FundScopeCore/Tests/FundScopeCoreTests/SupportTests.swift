import Foundation
import Testing
@testable import FundScopeCore

@Suite struct MarketCalendarTests {
    let calendar = MarketCalendar(holidays: [DateComponents(year: 2026, month: 11, day: 9)])

    @Test func sessionTimes() {
        #expect(calendar.status(at: ist(2026, 10, 26, 9, 0)) == .preOpen)
        #expect(calendar.status(at: ist(2026, 10, 26, 9, 15)) == .open)
        #expect(calendar.status(at: ist(2026, 10, 26, 15, 29)) == .open)
        #expect(calendar.status(at: ist(2026, 10, 26, 15, 30)) == .closed)
        #expect(calendar.status(at: ist(2026, 10, 31, 11, 0)) == .closed) // Saturday
        #expect(calendar.status(at: ist(2026, 11, 9, 11, 0)) == .holiday)
    }

    @Test func previousTradingDaySkipsWeekendAndHoliday() {
        #expect(calendar.previousTradingDay(before: ist(2026, 10, 26, 12)) == ist(2026, 10, 23))
        #expect(calendar.previousTradingDay(before: ist(2026, 11, 10, 12)) == ist(2026, 11, 6))
    }
}

@Suite struct FinanceFormatTests {
    @Test func indianGrouping() {
        #expect(FinanceFormat.currency(Decimal(string: "123456.78")!) == "₹1,23,456.78")
        #expect(FinanceFormat.units(Decimal(string: "1234.5")!) == "1,234.500")
        #expect(FinanceFormat.nav(Decimal(string: "45.1")!) == "45.1000")
    }

    @Test func compact() {
        #expect(FinanceFormat.compactCurrency(12_345_678) == "₹1.23 Cr")
        #expect(FinanceFormat.compactCurrency(250_000) == "₹2.50 L")
        #expect(FinanceFormat.compactCurrency(-250_000) == "−₹2.50 L")
    }

    @Test func negativeCurrencyUsesMinusSign() {
        #expect(FinanceFormat.currency(Decimal(string: "-0.15")!, signed: true) == "−₹0.15")
    }

    @Test func signedPoints() {
        #expect(FinanceFormat.points(Decimal(string: "22960.354")!) == "22,960.35")
        #expect(FinanceFormat.points(Decimal(string: "23.6")!, signed: true) == "+23.60")
        #expect(FinanceFormat.points(Decimal(string: "-23.6")!, signed: true) == "−23.60")
        #expect(FinanceFormat.points(Decimal(string: "-0.001")!, signed: true) == "0.00")
    }

    @Test func signedPercent() {
        #expect(FinanceFormat.percent(Decimal(string: "1.234")!) == "+1.23%")
        #expect(FinanceFormat.percent(Decimal(string: "-1.236")!) == "−1.24%")
        #expect(FinanceFormat.percent(0) == "0.00%")
        #expect(FinanceFormat.bps(percentPoints: Decimal(string: "0.123")!) == "+12.3 bps")
    }
}

@Suite struct DemoDataTests {
    @Test func deterministicAndConsistent() {
        let now = ist(2026, 10, 27, 11, 30)
        let a = DemoData.make(now: now), b = DemoData.make(now: now)
        #expect(a.quotes == b.quotes)
        #expect(a.sessionIsLive)
        // Official NAV ends on the trading day before the session.
        #expect(a.navHistory["900101"]?.last?.date == ist(2026, 10, 26))
        // Every disclosure adds up to 100% within rounding.
        for list in a.disclosures.values {
            for d in list {
                let total = d.holdings.reduce(Decimal(0)) { $0 + $1.weight }
                #expect(abs(total - 100) < Decimal(string: "0.2")!)
            }
        }
    }

    @Test func weekendUsesLastSession() {
        let data = DemoData.make(now: ist(2026, 10, 31, 11, 0))
        #expect(!data.sessionIsLive)
        #expect(data.sessionDay == ist(2026, 10, 30))
    }
}

@Suite struct RoundingEdgeTests {
    @Test func tinyNegativePercentHasNoSign() {
        #expect(FinanceFormat.percent(Decimal(string: "-0.001")!) == "0.00%")
        #expect(FinanceFormat.wholeCurrency(Decimal(string: "123456.78")!) == "₹1,23,457")
    }

    @Test func overshootIsNotNegativeExposure() {
        let over = Disclosure(fundCode: "O", disclosureDate: ist(2026, 9, 30), holdings: [equity("X", Decimal(string: "100.02")!)])
        let rows = LookThrough.exposure(positions: [(100, over)]) { ($0.isin, $0.name) }
        #expect(rows.allSatisfy { $0.value >= 0 })
        #expect(rows.first { $0.id == LookThrough.unmappedKey } == nil)
    }
}

let importNow = ist(2026, 10, 29, 12)
