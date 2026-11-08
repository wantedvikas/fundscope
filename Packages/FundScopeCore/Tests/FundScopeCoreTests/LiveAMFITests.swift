import Foundation
import Testing
@testable import FundScopeCore

/// Calls the real AMFI service. Off by default; run with `FUNDSCOPE_LIVE=1 swift test --filter LiveAMFI`.
/// No UI, no stored data: it only downloads public NAVs and checks them.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FUNDSCOPE_LIVE"] == "1"), .timeLimit(.minutes(10)))
struct LiveAMFITests {
    @Test func dailyFileContainsWatchedFunds() async throws {
        let records = AMFI.parse(try await AMFI.download())
        #expect(records.count > 10_000)
        for (_, code) in FundMatcherTests.expected {
            #expect(records.contains { $0.code == code }, "AMFI no longer lists \(code)")
        }
    }

    @Test func fiveYearBackfillForAllWatchedFunds() async throws {
        let today = Date.now
        let jobs = FundMatcherTests.expected.flatMap { name, code in
            AMFIHistory.missingRanges(earliest: nil, latest: nil, today: today).map { (name, code, $0.from, $0.to) }
        }
        var points: [String: [NAVPoint]] = [:]
        try await withThrowingTaskGroup(of: (String, [NAVPoint]).self) { group in
            var pending = jobs[...]
            for _ in 0..<3 {
                if let j = pending.popFirst() { group.addTask { (j.1, try await AMFIHistory.fetch(code: j.1, from: j.2, to: j.3)) } }
            }
            for try await (code, result) in group {
                points[code, default: []] += result
                if let j = pending.popFirst() { group.addTask { (j.1, try await AMFIHistory.fetch(code: j.1, from: j.2, to: j.3)) } }
            }
        }
        let calendar = MarketCalendar().calendar
        for (name, code) in FundMatcherTests.expected {
            let series = (points[code] ?? []).sorted { $0.date < $1.date }
            #expect(!series.isEmpty, "\(name): no history")
            #expect(Set(series.map(\.date)).count == series.count, "\(name): chunks overlap")
            if let last = series.last {
                #expect(calendar.dateComponents([.day], from: last.date, to: today).day! <= 5, "\(name): newest NAV is old")
            }
            print("\(name): \(series.count) NAVs, \(series.first.map { FinanceFormat.date($0.date) } ?? "—") to \(series.last.map { FinanceFormat.date($0.date) } ?? "—")")
        }
    }
}
