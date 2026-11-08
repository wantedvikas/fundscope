import Foundation
import SwiftData
import Testing
@testable import FundScopeCore

func fixture(_ name: String) -> URL {
    Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil)!
}

let amfiRecords: [SchemeRecord] = AMFI.parse(try! String(contentsOf: fixture("amfi_navall_subset.txt"), encoding: .utf8))

@Suite struct AMFIParserTests {
    @Test func parsesCurrentLayout() throws {
        #expect(amfiRecords.count == 78)
        let bandhan = try #require(amfiRecords.first { $0.code == "147946" })
        #expect(bandhan.name == "BANDHAN Small Cap Fund")
        #expect(bandhan.isin == "INF194KB1AL4")
        #expect(bandhan.nav == Decimal(string: "54.012"))
        #expect(bandhan.date == ist(2026, 10, 28))
        #expect(bandhan.category == "Equity Scheme - Small Cap Fund")
        #expect(bandhan.shortCategory == "Small Cap Fund")
        #expect(bandhan.amc == "Bandhan Mutual Fund")
        #expect(bandhan.isDirect && bandhan.isGrowth && bandhan.isEstimableCategory)
    }

    @Test func hybridIsCandidateButFoFIsNot() throws {
        let arbitrage = try #require(amfiRecords.first { $0.code == "120401" })
        #expect(arbitrage.fundInfo.isEstimable)
        let fof = try #require(amfiRecords.first { $0.code == "154449" })
        #expect(!fof.fundInfo.isEstimable)
    }

    @Test func olderSixColumnLayoutAndNA() {
        let text = """
        Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Net Asset Value;Date

        Open Ended Schemes(Equity Scheme - Mid Cap Fund)

        Demo Mutual Fund

        100001;INF000D01011;-;Demo Mid Cap Fund - Direct Plan - Growth;123.45;01-Oct-2026
        100002;INF000D01029;-;Demo Mid Cap Fund - Direct Plan - IDCW;N.A.;01-Oct-2026
        """
        let records = AMFI.parse(text)
        #expect(records.count == 2)
        #expect(records[0].isDirect && records[0].isGrowth)
        #expect(records[0].amc == "Demo Mutual Fund")
        #expect(records[1].nav == nil)
        #expect(!records[1].isGrowth)
    }
}

@Suite struct FundMatcherTests {
    /// Fund names as a holdings export spells them (short forms included), and the AMFI Direct Growth scheme each must find.
    static let expected: [(String, String)] = [
        ("Bandhan Small Cap Fund", "147946"), ("ICICI Pru Large & Mid Cap Fund", "120596"),
        ("ICICI Pru Multi Asset Allocation Fund", "120334"), ("Parag Parikh Flexi Cap Fund", "122639"),
        ("WOC Mid Cap Fund", "150584"), ("Abakkus Small Cap Fund", "154215"),
        ("Invesco India Arbitrage Fund", "120401"), ("Invesco India Smallcap Fund", "145137"),
        ("Nippon India Large Cap Fund", "118632"), ("Nippon India Growth Mid Cap Fund", "118668"),
        ("HDFC Flexi Cap Fund", "118955"), ("HDFC Mid Cap Fund", "118989"),
        ("ICICI Pru Large Cap Fund", "120586"), ("WOC Flexi Cap Fund", "150346"),
        ("Quant Small Cap Fund", "120828"), ("SBI Small Cap Fund", "125497"), ("Axis Large Cap Fund", "120465"),
        ("Mirae Asset Large Cap Fund", "118825"), ("UTI Nifty 50 Index Fund", "120716"),
    ]

    @Test(arguments: expected)
    func findsDirectGrowthScheme(name: String, code: String) {
        #expect(FundMatcher.bestMatch(name, in: amfiRecords)?.code == code)
    }

    @Test func disclosureTitlesNeedTheSameWords() {
        #expect(FundMatcher.sameScheme("NIPPON INDIA LARGE CAP FUND", "Nippon India Large Cap Fund"))
        #expect(FundMatcher.sameScheme("ICICI Prudential Large Cap Fund", "ICICI Prudential Large Cap Fund (erstwhile Bluechip Fund)"))
        #expect(FundMatcher.sameScheme("Invesco India Small cap Fund", "Invesco India Smallcap Fund"))
        #expect(!FundMatcher.sameScheme("Nippon India Multi Cap Fund", "Nippon India Large Cap Fund"))
        #expect(!FundMatcher.sameScheme("Abakkus Large & Mid Cap Fund", "ICICI Prudential Large & Mid Cap Fund"))
        #expect(!FundMatcher.sameScheme("HDFC Mid Cap Fund", "HDFC Mid Cap Opportunities Fund"))
    }

    @Test func regularPlanWhenAsked() {
        #expect(FundMatcher.bestMatch("HDFC Flexi Cap", in: amfiRecords, direct: false)?.code == "101762")
    }

    @Test func vagueQueryNeedsAPick() {
        #expect(FundMatcher.bestMatch("Small Cap Growth Opportunities", in: amfiRecords) == nil)
        #expect(!FundMatcher.search("small cap", in: amfiRecords).isEmpty)
    }
}

@Suite struct FundListReaderTests {
    @Test func readsOnlyNamesAndPlan() throws {
        let entries = FundListReader.entries(try TableReader.read(fixture("fund_list_holdings.csv")))
        #expect(entries.count == 9)
        #expect(entries.first == .init(name: "Quant Small Cap Fund", direct: true))
        #expect(!entries.contains { $0.name == "Total" })
        // Every name in the file resolves to exactly the expected scheme.
        let codes = entries.compactMap { FundMatcher.bestMatch($0.name, in: amfiRecords, direct: $0.direct)?.code }
        #expect(codes == ["120828", "122639", "120465", "118989", "125497", "150584", "120716", "120596", "118825"])
    }
}

@MainActor @Suite struct WatchlistStoreTests {
    func context() throws -> ModelContext {
        let c = ModelContext(try WatchlistStore.container(directory: nil))
        c.autosaveEnabled = false
        return c
    }

    func schemes(_ codes: [String]) -> [SchemeRecord] { codes.compactMap { c in amfiRecords.first { $0.code == c } } }

    @Test func addIsIdempotentAndKeepsOrder() throws {
        let ctx = try context()
        #expect(try WatchlistStore.add(schemes(["147946", "122639"]), now: importNow, context: ctx) == 2)
        #expect(try WatchlistStore.add(schemes(["122639", "118955"]), now: importNow.addingTimeInterval(60), context: ctx) == 1)
        #expect(try WatchlistStore.items(ctx).map(\.code) == ["147946", "122639", "118955"])
    }

    @Test func navHistoryGrowsOnePointPerDayAndNeverOverwrites() throws {
        let ctx = try context()
        let bandhan = schemes(["147946"])
        try WatchlistStore.add(bandhan, now: importNow, context: ctx)
        let b = bandhan[0]
        let changedSameDay = SchemeRecord(code: b.code, isin: b.isin, name: b.name, plan: b.plan, option: b.option, nav: 99,
                                          date: b.date, amc: b.amc, category: b.category)
        let nextDay = SchemeRecord(code: b.code, isin: b.isin, name: b.name, plan: b.plan, option: b.option, nav: 55,
                                   date: ist(2026, 10, 29), amc: b.amc, category: b.category)
        try WatchlistStore.recordNAVs([changedSameDay, nextDay], now: importNow, context: ctx)
        try ctx.save()
        let data = try WatchlistStore.dataset(ctx, directory: [b.code: b], amfi: .init(fetchedAt: importNow, error: nil, schemeCount: 73), now: importNow)
        #expect(data.navHistory[b.code]?.map(\.nav) == [Decimal(string: "54.012")!, 55])
        let watched = Analytics.watched(data)
        #expect(watched[0].officialChange.map { abs($0 - Decimal(string: "1.8292")!) < Decimal(string: "0.001")! } == true)
        #expect(watched[0].fund.category == "Small Cap Fund")
    }

    @Test func removeDeletesNAVsToo() throws {
        let ctx = try context()
        try WatchlistStore.add(schemes(["147946"]), now: importNow, context: ctx)
        try WatchlistStore.remove(code: "147946", context: ctx)
        #expect(try ctx.fetchCount(FetchDescriptor<StoredNAV>()) == 0)
        #expect(try WatchlistStore.items(ctx).isEmpty)
    }

    @Test func amfiFailureIsVisibleNotHidden() throws {
        let ctx = try context()
        let data = try WatchlistStore.dataset(ctx, directory: [:], amfi: .init(fetchedAt: nil, error: "Offline.", schemeCount: 0), now: importNow)
        #expect(data.dataSources.first { $0.name == "AMFI" }?.status == .unavailable)
    }

    @Test func legacyStoreIsDeleted() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for s in ["", "-shm", "-wal"] { try Data("x".utf8).write(to: dir.appending(path: "FundScope.store\(s)")) }
        WatchlistStore.removeLegacyStore(in: dir)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path(percentEncoded: false)).isEmpty)
    }
}

@Suite struct EqualWeightTests {
    @Test func everyFundCountsTheSame() {
        let data = DemoData.make(now: ist(2026, 10, 27, 11, 30))
        let sectors = Analytics.exposures(data) { ($0.sector, $0.sector) }
        // Disclosure weights are rounded, so totals land within a fraction of a percent of 100.
        #expect(abs(sectors.reduce(Decimal(0)) { $0 + $1.share } - 100) < Decimal(string: "0.5")!)
        let watched = Analytics.watched(data)
        let expected = watched.compactMap { $0.estimate?.estimatedReturn }
        #expect(Analytics.averageEstimatedChange(watched) == expected.reduce(0, +) / Decimal(expected.count))
    }
}

@Suite struct ReaderTests {
    @Test func csvQuotesBOMAndSemicolons() throws {
        let rows = try TableReader.read(fixture("semicolon_bom.csv"))[0].rows
        #expect(rows == [["ISIN", "Scheme", "Units"], ["INF000M01011", "Meridian; Flexi \"Cap\"", "10.5"]])
    }

    @Test func csvNewlineInsideQuotes() {
        #expect(CSVReader.parse("a,b\n\"x\ny\",2\n") == [["a", "b"], ["x\ny", "2"]])
    }

    @Test func xlsxSheetsAndSharedStrings() throws {
        let sheets = try TableReader.read(fixture("two_sheets.xlsx"))
        #expect(sheets.map(\.name) == ["Notes", "Mutual Funds"])
        #expect(sheets[1].rows[3][1] == "INF000M01011")
        #expect(FundListReader.entries(sheets).map(\.name).first == "MERIDIAN FLEXI CAP FUND - DIRECT PLAN")
    }

    @Test func rejectsOtherFileTypes() {
        #expect(throws: TableReadError.self) { try TableReader.read(URL(filePath: "/tmp/x.pdf")) }
    }
}

@Suite struct AMFIHistoryTests {
    func load(_ name: String) throws -> Data { try Data(contentsOf: fixture(name)) }

    @Test func parsesRealResponseExactly() throws {
        let points = try AMFIHistory.parse(try load("amfi_history_ppfas_3y.json"))
        #expect(points.count == 739)
        #expect(points.first?.date == ist(2023, 10, 30))
        #expect(points.last == NAVPoint(date: ist(2026, 10, 28), nav: Decimal(string: "88.8018")!))
        #expect(points == points.sorted { $0.date < $1.date })
    }

    @Test func noRecordsIsEmptyAndErrorThrows() throws {
        #expect(try AMFIHistory.parse(Data(#"{"message":"No records to display"}"#.utf8)).isEmpty)
        #expect(throws: AMFIHistory.FetchError.server("from_date to to_date range must be less than 5 years")) {
            try AMFIHistory.parse(Data(#"{"error":"from_date to to_date range must be less than 5 years"}"#.utf8))
        }
    }

    @Test func urlUsesSchemeCodeAndISTDays() {
        let url = AMFIHistory.url(code: "122639", from: ist(2023, 10, 30), to: ist(2026, 10, 28)).absoluteString
        #expect(url == "https://www.amfiindia.com/api/nav-history?query_type=historical_period&from_date=2023-10-30&to_date=2026-10-28&sd_id=122639")
    }

    @Test func emptyFundGetsFiveYearsInChunksUnderLimit() {
        let ranges = AMFIHistory.missingRanges(earliest: nil, latest: nil, today: ist(2026, 10, 29, 20))
        #expect(ranges.count == 2)
        #expect(ranges.first?.to == ist(2026, 10, 29))
        #expect(ranges.last?.from == ist(2021, 10, 30))
        let cal = MarketCalendar().calendar
        #expect(ranges.allSatisfy { $0.from <= $0.to })
        for r in ranges { #expect(cal.date(byAdding: .year, value: AMFIHistory.maxSpanYears, to: r.from)! > r.to) }
        // Chunks touch without gaps or overlaps.
        #expect(cal.date(byAdding: .day, value: 1, to: ranges[1].to) == ranges[0].from)
    }

    @Test func onlyMissingPartsAreFetched() {
        let today = ist(2026, 10, 29, 20)
        // Up to date (newest NAV is the previous trading day): nothing to fetch.
        #expect(AMFIHistory.missingRanges(earliest: ist(2021, 11, 1), latest: ist(2026, 10, 28), today: today).isEmpty)
        // App not opened for a week: only the gap.
        let gap = AMFIHistory.missingRanges(earliest: ist(2021, 11, 1), latest: ist(2026, 10, 21), today: today)
        #expect(gap.count == 1 && gap[0].from == ist(2026, 10, 22) && gap[0].to == ist(2026, 10, 29))
        // A fund launched in 2022 whose history was already checked back to 2021: nothing more to fetch.
        #expect(AMFIHistory.missingRanges(earliest: ist(2021, 10, 30), latest: ist(2026, 10, 28), today: today).isEmpty)
        // Only one day stored (the watchlist's first NAV): everything before it.
        let fresh = AMFIHistory.missingRanges(earliest: ist(2026, 10, 28), latest: ist(2026, 10, 28), today: today)
        #expect(fresh.first?.to == ist(2026, 10, 27))
        #expect(fresh.last?.from == ist(2021, 10, 30))
    }

    @MainActor @Test func historyIsStoredOnceAndBecomesOneDayChange() throws {
        let ctx = ModelContext(try WatchlistStore.container(directory: nil))
        let bandhan = try #require(amfiRecords.first { $0.code == "147946" })
        try WatchlistStore.add([bandhan], now: importNow, context: ctx)
        let points = try AMFIHistory.parse(try load("amfi_history_bandhan_2m.json"))
        let added = try WatchlistStore.recordHistory(code: "147946", points: points, now: importNow, context: ctx)
        #expect(added == points.count - 1) // 28 Oct was already stored from the daily file
        #expect(try WatchlistStore.recordHistory(code: "147946", points: points, now: importNow, context: ctx) == 0)
        let span = try #require(try WatchlistStore.historySpan(code: "147946", context: ctx))
        #expect(span.earliest == ist(2026, 9, 1) && span.latest == ist(2026, 10, 28))
        let data = try WatchlistStore.dataset(ctx, directory: ["147946": bandhan], amfi: .init(fetchedAt: importNow, error: nil, schemeCount: 1), now: importNow)
        #expect(Analytics.watched(data)[0].officialChange != nil)
    }
}

@Suite struct ReaderFormatTests {
    @Test func modernWorkbookNamedXLSIsRead() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let renamed = dir.appending(path: "portfolio.xls")
        try FileManager.default.copyItem(at: fixture("two_sheets.xlsx"), to: renamed)
        #expect(try TableReader.read(renamed).map(\.name) == ["Notes", "Mutual Funds"])
        // Old binary Excel (starts D0 CF 11 E0) gets a clear message instead of garbage.
        let old = dir.appending(path: "old.xls")
        try Data([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]).write(to: old)
        #expect(throws: TableReadError.unsupportedFile("xls")) { try TableReader.read(old) }
    }
}
