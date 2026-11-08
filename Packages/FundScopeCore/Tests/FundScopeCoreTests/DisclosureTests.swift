import Foundation
import SwiftData
import Testing
@testable import FundScopeCore

/// Real PPFAS Flexi Cap disclosures (public files, Aug and Sep 2026).
@Suite struct DisclosureParserTests {
    func parsed(_ month: String) throws -> DisclosureParser.Parsed {
        try #require(DisclosureParser.parse(try TableReader.read(fixture("ppfas_ppfcf_\(month).xlsx"))).first)
    }

    @Test func readsTitleDateAndTotal() throws {
        let p = try parsed("2026-09")
        #expect(p.title == "Parag Parikh Flexi Cap Fund")
        #expect(p.date == ist(2026, 9, 30))
        #expect(abs(p.totalWeight - 100) < Decimal(string: "0.05")!)
        #expect(p.warnings.isEmpty)
    }

    @Test func fractionsBecomePercents() throws {
        let hdfc = try #require(try parsed("2026-09").holdings.first { $0.security?.isin == "INE040A01034" })
        #expect(hdfc.weight == Decimal(string: "7.75"))
        #expect(hdfc.assetType == .equity)
        #expect(hdfc.security?.sector == "Banks")
        #expect(hdfc.quantity == 158_729_224)
    }

    @Test func sectionsDecideAssetTypes() throws {
        let h = try parsed("2026-09").holdings
        func weight(_ type: AssetType) -> Decimal { h.filter { $0.assetType == type }.reduce(0) { $0 + $1.weight } }
        // From the file's own sub-totals.
        #expect(abs(weight(.equity) - Decimal(string: "72.06")!) < Decimal(string: "0.05")!)
        #expect(abs(weight(.hedged) - Decimal(string: "1.44")!) < Decimal(string: "0.05")!)
        #expect(abs(weight(.foreignEquity) - Decimal(string: "11.90")!) < Decimal(string: "0.05")!)
        #expect(abs(weight(.other) - Decimal(string: "6.27")!) < Decimal(string: "0.05")!) // REITs
        #expect(abs(weight(.fundUnits) - Decimal(string: "0.60")!) < Decimal(string: "0.05")!)
        #expect(h.contains { $0.rawName.hasPrefix("TRP_") && $0.assetType == .cash })
        #expect(h.contains { $0.rawName.lowercased().contains("net receivables") && $0.weight < 0 })
        // Futures listed after GRAND TOTAL are not part of the portfolio.
        #expect(!h.contains { $0.rawName.contains("Future") })
        #expect(h.first { $0.security?.isin == "US02079K3059" }?.assetType == .foreignEquity)
    }

    @Test func percentTextIsNotScaledAgain() throws {
        // "$0.00%" rows (less than 0.01%) must stay tiny, not become 0.00% × 100.
        let bel = try #require(try parsed("2026-09").holdings.first { $0.security?.isin == "INE263A01024" })
        #expect(bel.weight == 0)
        #expect(bel.assetType == .hedged)
    }

    @Test func ppfasFlexiCapIsNotEstimableUnderV1Rules() throws {
        let p = try parsed("2026-09")
        let e = NAVEstimator.estimate(holdings: p.holdings, quotes: [:], baselineNAV: 88, now: .now)
        guard case .notEstimable = e.status else { Issue.record("expected not estimable"); return }
        #expect(e.unsupportedWeight > 10)
    }

    @Test func monthOverMonthDiffWorksOnRealFiles() throws {
        let aug = try parsed("2026-08"), sep = try parsed("2026-09")
        let changes = DisclosureDiff.compare(old: Disclosure(fundCode: "122639", disclosureDate: aug.date!, holdings: aug.holdings),
                                             new: Disclosure(fundCode: "122639", disclosureDate: sep.date!, holdings: sep.holdings))
        #expect(!changes.isEmpty)
        #expect(changes.filter { $0.isQuantityConfirmed }.count > 20)
        // Cash and debt roll over every month (TREPS is renamed, CDs mature); they aren't buy/sell decisions.
        #expect(!changes.contains { $0.name.hasPrefix("TRP_") || $0.name.contains("(") && $0.sector == nil })
    }

    @Test func statementDates() {
        #expect(DisclosureParser.statementDate("Monthly Portfolio Statement as on September 30, 2026") == ist(2026, 9, 30))
        #expect(DisclosureParser.statementDate("Portfolio as on 30-Sep-2026 (Unaudited)") == ist(2026, 9, 30))
        #expect(DisclosureParser.statementDate("as on 30.09.2026") == ist(2026, 9, 30))
        #expect(DisclosureParser.statementDate("No date here") == nil)
    }

    @Test func percentLayoutAndNoGrandTotal() {
        let sheet = RawSheet(name: "HDF01", rows: [
            ["HDFC Mid Cap Fund (An open ended equity scheme)"],
            ["Portfolio as on 30-Sep-2026"],
            ["Name of Instrument", "ISIN", "Industry", "Quantity", "Market Value (Rs. Lakh)", "% to NAV"],
            ["EQUITY & EQUITY RELATED"],
            ["Demo Bank Ltd", "INE000A01011", "Banks", "100", "10", "60.00"],
            ["Demo Tech Ltd", "INE000B01012", "IT - Software", "50", "5", "35.5"],
            ["TREPS", "", "", "", "1", "4.5"],
        ])
        let p = DisclosureParser.parse([sheet]).first
        #expect(p?.title == "HDFC Mid Cap Fund")
        #expect(p?.holdings.map(\.weight) == [60, Decimal(string: "35.5")!, Decimal(string: "4.5")!])
        #expect(p?.holdings.last?.assetType == .cash)
    }

    /// ICICI's layout: fund house name first, headings carry subtotals, ends at "Total Net Assets".
    @Test func headingSubtotalsAreNotHoldings() throws {
        let sheet = RawSheet(name: "BLUECHIP", rows: [
            ["", "ICICI Prudential Mutual Fund"],
            ["", "ICICI Prudential Large Cap Fund"],
            ["", "Portfolio as on Sep 30,2026"],
            ["", "Company/Issuer/Instrument Name", "ISIN", "Coupon", "Industry/Rating", "Quantity", "Exposure/Market Value(Rs.Lakh)", "% to Nav"],
            ["", "Equity & Equity Related Instruments", "", "", "", "", "960", "0.96"],
            ["", "Listed / Awaiting Listing On Stock Exchanges", "", "", "", "", "960", "0.96"],
            ["", "ICICI Bank Ltd.", "INE090A01021", "", "Banks", "100", "560", "0.56"],
            ["", "HDFC Bank Ltd.", "INE040A01034", "", "Banks", "100", "400", "0.40"],
            ["", "Money Market Instruments", "", "", "", "", "15", "0.015"],
            ["", "Treasury Bills", "", "", "", "", "15", "0.015"],
            ["", "91 Days Treasury Bills", "IN002026X131", "", "SOV", "1", "15", "0.015"],
            ["", "TREPS", "", "", "", "", "20", "0.02"],
            ["", "Others", "", "", "", "", "10", "0.01"],
            ["", "Cash Margin - Derivatives", "", "", "", "", "10", "0.01"],
            ["", "Net Current Assets", "", "", "", "", "-5", "-0.005"],
            ["", "Total Net Assets", "", "", "", "", "1000", "1"],
            ["", "Notes", "IN0000000000", "", "", "", "", "0.5"],
        ])
        let p = try #require(DisclosureParser.parse([sheet]).first)
        #expect(p.title == "ICICI Prudential Large Cap Fund")
        #expect(p.date == ist(2026, 9, 30))
        #expect(p.holdings.map(\.rawName) == ["ICICI Bank Ltd.", "HDFC Bank Ltd.", "91 Days Treasury Bills", "TREPS", "Cash Margin - Derivatives", "Net Current Assets"])
        #expect(p.holdings.first?.weight == 56)
        #expect(p.totalWeight == 100)
        #expect(p.warnings.isEmpty)
    }

    /// Real Invesco Arbitrage file (Sep 2026): short futures sit inside the main table.
    @Test func arbitragePairsNetToFlat() throws {
        let p = try #require(DisclosureParser.parse(try TableReader.read(fixture("invesco_arbitrage_2026-09.xlsx"))).first)
        #expect(abs(p.totalWeight - 100) < Decimal(string: "0.1")!)
        #expect(p.warnings.isEmpty)
        func weight(_ type: AssetType) -> Decimal { p.holdings.filter { $0.assetType == type }.reduce(0) { $0 + $1.weight } }
        // 79.58% stock long and 79.94% futures short net to almost nothing; no fake stock exposure remains.
        #expect(abs(weight(.hedged)) < 1)
        #expect(weight(.equity) < 1)
        #expect(p.holdings.first { $0.rawName == "HDFC Bank Limited" }?.assetType == .hedged)
        #expect(DisclosureParser.futureCompany("HDFC Bank Limited November 2026 Future") == "hdfc bank limited")
    }

    /// Real Bandhan Small Cap file (Sep 2026): "Net Current Assets" is a summary its grand total excludes.
    @Test func summaryLineOutsideTheGrandTotalIsDropped() throws {
        let p = try #require(DisclosureParser.parse(try TableReader.read(fixture("bandhan_smallcap_2026-09.xlsx"))).first)
        #expect(p.title == "Bandhan Small Cap Fund")
        #expect(p.date == ist(2026, 9, 30))
        #expect(abs(p.totalWeight - 100) < Decimal(string: "0.02")!)
        #expect(!p.holdings.contains { $0.rawName == "Net Current Assets" })
        #expect(p.holdings.contains { $0.rawName == "Net Receivables/Payables" }) // a real line stays
    }

    @Test func sheetWithoutTableIsIgnored() {
        #expect(DisclosureParser.parse([RawSheet(name: "Index", rows: [["Scheme list"], ["A", "B"]])]).isEmpty)
    }
}

@Suite struct DisclosureStoreTests {
    @Test func seedSavesStarterDisclosuresWithoutOverwriting() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "Seed \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let date = ist(2026, 9, 30)
        let kept = Disclosure(fundCode: "122639", disclosureDate: date, holdings: [])
        #expect(try DisclosureStore.save(kept, in: dir) == .saved)
        let starter = DisclosureStore.Starter(codes: ["122639", "120334"], disclosures: [
            Disclosure(fundCode: "122639", disclosureDate: date, holdings: [equity("X", 100)]),
            Disclosure(fundCode: "120334", disclosureDate: date, holdings: []),
        ])
        let file = dir.appending(path: "StarterFunds.json")
        try DisclosureStore.encoder.encode(starter).write(to: file)
        #expect(try DisclosureStore.seed(from: file, in: dir) == ["122639", "120334"])
        let loaded = DisclosureStore.load(codes: ["122639", "120334"], in: dir)
        #expect(loaded["122639"]?.first?.holdings.isEmpty == true)
        #expect(loaded["120334"]?.count == 1)
    }

    @Test func savesOncePerMonthAndLoadsSorted() throws {
        // A space in the path, like "Application Support", must not break the "already saved" check.
        let dir = FileManager.default.temporaryDirectory.appending(path: "Fund Scope \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sep = Disclosure(fundCode: "122639", disclosureDate: ist(2026, 9, 30), holdings: [equity("X", 100)], sourceTitle: "PPFCF")
        let aug = Disclosure(fundCode: "122639", disclosureDate: ist(2026, 8, 31), holdings: [equity("X", 90), other("Cash", .cash, 10)])
        #expect(try DisclosureStore.save(sep, in: dir) == .saved)
        #expect(try DisclosureStore.save(aug, in: dir) == .saved)
        let changed = Disclosure(fundCode: "122639", disclosureDate: ist(2026, 9, 30), holdings: [equity("Y", 100)])
        #expect(try DisclosureStore.save(changed, in: dir) == .alreadyHave)
        let loaded = DisclosureStore.load(codes: ["122639", "999"], in: dir)
        #expect(loaded["122639"]?.map(\.disclosureDate) == [ist(2026, 8, 31), ist(2026, 9, 30)])
        #expect(loaded["122639"]?.last == sep) // original kept, not overwritten
        #expect(loaded["999"] == nil)
    }
}

@MainActor @Suite struct DisclosureDatasetTests {
    @Test func importedHoldingsReachTheWatchlist() throws {
        let ctx = ModelContext(try WatchlistStore.container(directory: nil))
        let ppfas = try #require(amfiRecords.first { $0.code == "122639" })
        let hdfc = try #require(amfiRecords.first { $0.code == "118989" })
        try WatchlistStore.add([ppfas, hdfc], now: importNow, context: ctx)
        let parsed = try #require(DisclosureParser.parse(try TableReader.read(fixture("ppfas_ppfcf_2026-09.xlsx"))).first)
        let disclosure = Disclosure(fundCode: "122639", disclosureDate: parsed.date!, holdings: parsed.holdings)
        let data = try WatchlistStore.dataset(ctx, directory: ["122639": ppfas, "118989": hdfc],
                                              amfi: .init(fetchedAt: importNow, error: nil, schemeCount: 2),
                                              disclosures: ["122639": [disclosure], "000000": [disclosure]], now: importNow)
        #expect(data.disclosures.keys.sorted() == ["122639"]) // only watched funds
        #expect(data.securities.contains { $0.name == "HDFC Bank Limited" })
        let source = try #require(data.dataSources.first { $0.name == "AMC disclosures" })
        #expect(source.status == .stale)
        #expect(source.warning == "1 of 2 watched funds have no holdings imported yet")
        // Holdings without live prices: no estimate shown, rather than a broken one.
        #expect(Analytics.watched(data).first { $0.fund.code == "122639" }?.estimate == nil)
        #expect(Analytics.watched(data).first { $0.fund.code == "122639" }?.holdingsDate == ist(2026, 9, 30))
        let companies = Analytics.exposures(data) { ($0.isin, $0.name) }
        // Foreign stocks are companies the fund owns, not "cash, debt & other".
        #expect(companies.contains { $0.name == "Alphabet Inc A" })
        let other = try #require(companies.first { $0.id == LookThrough.nonEquityKey })
        #expect(other.share < 20)
        #expect(companies.first { $0.name == "HDFC Bank Limited" }.map { abs($0.share - Decimal(string: "7.75")!) < Decimal(string: "0.01")! } == true)
    }
}
