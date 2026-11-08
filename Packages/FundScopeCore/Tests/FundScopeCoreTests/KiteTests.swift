import Foundation
import SwiftData
import Testing
@testable import FundScopeCore

/// Kite payloads below follow the field names in kite.trade/docs/connect/v3 (market-quotes, user, exceptions).
/// They are hand-written, not captured from a live account.
@Suite struct KiteTests {
    @Test func checksumIsSHA256OfKeyTokenSecret() {
        #expect(Kite.checksum(apiKey: "kitekey", requestToken: "reqtok123", apiSecret: "secret")
            == "c68bdbfa051ba8a775885c1c07938ad33babd18bcdefb147c1d7b84a75e5118d")
    }

    @Test func loginURLCarriesStateThroughRedirectParams() {
        let url = Kite.loginURL(apiKey: "kitekey", state: "s1").absoluteString
        #expect(url == "https://kite.zerodha.com/connect/login?v=3&api_key=kitekey&redirect_params=state%3Ds1")
    }

    @Test func redirectIsCheckedBeforeUse() throws {
        let ok = URL(string: "http://127.0.0.1:7313/kite?action=login&type=login&status=success&request_token=abc&state=s1")!
        #expect(try Kite.requestToken(fromRedirect: ok, expectedState: "s1") == "abc")
        #expect(throws: Kite.KiteError.self) { try Kite.requestToken(fromRedirect: ok, expectedState: "other") }
        let cancelled = URL(string: "http://127.0.0.1:7313/kite?status=cancelled&state=s1")!
        #expect(throws: Kite.KiteError.self) { try Kite.requestToken(fromRedirect: cancelled, expectedState: "s1") }
    }

    @Test func sessionRequestIsPostWithChecksum() throws {
        let r = Kite.sessionRequest(apiKey: "kitekey", requestToken: "reqtok123", apiSecret: "secret")
        #expect(r.httpMethod == "POST")
        #expect(r.url?.absoluteString == "https://api.kite.trade/session/token")
        #expect(r.value(forHTTPHeaderField: "X-Kite-Version") == "3")
        let body = String(decoding: try #require(r.httpBody), as: UTF8.self)
        #expect(body == "api_key=kitekey&request_token=reqtok123&checksum=c68bdbfa051ba8a775885c1c07938ad33babd18bcdefb147c1d7b84a75e5118d")
        #expect(!body.contains("secret&") && !body.hasSuffix("=secret")) // the secret itself is never sent
    }

    @Test func quoteRequestAuthAndSymbols() {
        let r = Kite.quoteRequest(symbols: ["NSE:HDFCBANK", "NSE:ITC"], apiKey: "k", accessToken: "t")
        #expect(r.url?.absoluteString == "https://api.kite.trade/quote?i=NSE:HDFCBANK&i=NSE:ITC")
        #expect(r.value(forHTTPHeaderField: "Authorization") == "token k:t")
    }

    @Test func parsesQuotesAndSkipsMissing() throws {
        let json = """
        {"status":"success","data":{
          "NSE:HDFCBANK":{"instrument_token":341249,"timestamp":"2026-10-29 11:30:05","last_trade_time":"2026-10-29 11:30:04",
            "last_price":1712.4,"volume":100,"ohlc":{"open":1700,"high":1720,"low":1695,"close":1698.15}},
          "NSE:ITC":{"instrument_token":424961,"timestamp":"2026-10-29 11:30:05","last_price":0,"ohlc":{"close":410.2}}
        }}
        """
        let quotes = try Kite.parseQuotes(Data(json.utf8), status: 200,
                                          symbolToISIN: ["NSE:HDFCBANK": "INE040A01034", "NSE:ITC": "INE154A01025", "NSE:INFY": "INE009A01021"],
                                          fallbackTime: .distantPast)
        let hdfc = try #require(quotes["INE040A01034"])
        #expect(hdfc.price == Decimal(string: "1712.4"))
        #expect(hdfc.previousClose == Decimal(string: "1698.15"))
        #expect(hdfc.exchangeTime == ist(2026, 10, 29, 11, 30).addingTimeInterval(5))
        #expect(quotes["INE154A01025"] == nil) // a zero price is not a price
        #expect(quotes["INE009A01021"] == nil) // absent from the response
    }

    @Test func errorsMapToRecoverableStates() {
        let token = Data(#"{"status":"error","message":"Incorrect `api_key` or `access_token`.","error_type":"TokenException"}"#.utf8)
        #expect(throws: Kite.KiteError.authRequired) { try Kite.parseQuotes(token, status: 403, symbolToISIN: [:], fallbackTime: .now) }
        #expect(throws: Kite.KiteError.rateLimited) { try Kite.parseQuotes(Data("{}".utf8), status: 429, symbolToISIN: [:], fallbackTime: .now) }
        let input = Data(#"{"status":"error","message":"Bad instrument","error_type":"InputException"}"#.utf8)
        #expect(throws: Kite.KiteError.server(type: "InputException", message: "Bad instrument")) {
            try Kite.parseQuotes(input, status: 400, symbolToISIN: [:], fallbackTime: .now)
        }
    }

    @Test func nseListMapsISINToSymbol() throws {
        let map = NSESymbols.parse(try String(contentsOf: fixture("nse_equity_subset.csv"), encoding: .utf8))
        #expect(map.count == 7)
        #expect(map["INE040A01034"] == "HDFCBANK")
        #expect(map["INE752E01010"] == "POWERGRID")
    }

    @Test func keychainRoundTrip() throws {
        let keychain = Keychain(service: "com.vikasghodke.FundScope.tests.\(UUID().uuidString)")
        defer { Keychain.Item.allCases.forEach { try? keychain.delete($0) } }
        #expect(keychain.get(.apiKey) == nil)
        try keychain.set("first", for: .apiKey)
        try keychain.set("second", for: .apiKey)
        #expect(keychain.get(.apiKey) == "second")
        try keychain.delete(.apiKey)
        #expect(keychain.get(.apiKey) == nil)
    }

    @Test func loopbackListenerCatchesTheRedirect() async throws {
        async let caught = LoginCallback.wait(port: 7399, timeout: .seconds(10))
        try await Task.sleep(for: .milliseconds(300))
        let (body, _) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:7399/kite?status=success&request_token=xyz&state=s9")!)
        #expect(String(decoding: body, as: UTF8.self).contains("You can close this tab"))
        #expect(try Kite.requestToken(fromRedirect: try await caught, expectedState: "s9") == "xyz")
    }
}

@MainActor @Suite struct LiveEstimateTests {
    func dataset(now: Date) throws -> Dataset {
        let ctx = ModelContext(try WatchlistStore.container(directory: nil))
        let hdfcMid = try #require(amfiRecords.first { $0.code == "118989" }) // official NAV 216.183 on 28 Oct
        try WatchlistStore.add([hdfcMid], now: importNow, context: ctx)
        let holdings = [equity("INE040A01034", 95), other("TREPS", .cash, 5)]
        let quote = Quote(isin: "INE040A01034", price: 102, previousClose: 100, exchangeTime: now.addingTimeInterval(-30))
        return try WatchlistStore.dataset(ctx, directory: ["118989": hdfcMid], amfi: .init(fetchedAt: importNow, error: nil, schemeCount: 1),
                                          disclosures: ["118989": [Disclosure(fundCode: "118989", disclosureDate: ist(2026, 9, 30), holdings: holdings)]],
                                          market: .init(quotes: ["INE040A01034": quote]), now: now)
    }

    @Test func estimatesFromLivePricesWhenBaselineMatches() throws {
        let data = try dataset(now: ist(2026, 10, 29, 11, 30))
        let e = try #require(Analytics.watched(data).first?.estimate)
        #expect(e.status == .ok)
        // 95% × +2% = +1.90% on the 28 Oct official NAV.
        #expect(e.estimatedReturn == Decimal(string: "1.9"))
        #expect(e.estimatedNAV == Decimal(string: "216.183")! * Decimal(string: "1.019")!)
        #expect(data.sessionIsLive)
    }

    /// After the close, small caps' last trades are hours old but still today's prices.
    @Test func thinlyTradedStocksCountAfterTheClose() throws {
        let ctx = ModelContext(try WatchlistStore.container(directory: nil))
        let hdfcMid = try #require(amfiRecords.first { $0.code == "118989" })
        try WatchlistStore.add([hdfcMid], now: importNow, context: ctx)
        let now = ist(2026, 10, 29, 16, 48)
        let holdings = [equity("LIQUID", 50), equity("THIN", 40), equity("NOTRADE", 5), other("TREPS", .cash, 5)]
        let quotes = [
            "LIQUID": Quote(isin: "LIQUID", price: 102, previousClose: 100, exchangeTime: ist(2026, 10, 29, 15, 59)),
            "THIN": Quote(isin: "THIN", price: 99, previousClose: 100, exchangeTime: ist(2026, 10, 29, 14, 10)),
            // No trade today: its newest quote is from yesterday's session.
            "NOTRADE": Quote(isin: "NOTRADE", price: 100, previousClose: 100, exchangeTime: ist(2026, 10, 28, 15, 20)),
        ]
        let data = try WatchlistStore.dataset(ctx, directory: ["118989": hdfcMid], amfi: .init(fetchedAt: importNow, error: nil, schemeCount: 1),
                                              disclosures: ["118989": [Disclosure(fundCode: "118989", disclosureDate: ist(2026, 9, 30), holdings: holdings)]],
                                              market: .init(quotes: quotes), now: now)
        let e = try #require(Analytics.watched(data).first?.estimate)
        #expect(e.pricedWeight == 90)
        #expect(e.unpricedWeight == 5)
        #expect(e.status == .ok)
    }

    @Test func refusesWhenOfficialNAVIsADayBehind() throws {
        // On 30 Oct the previous close is 29 Oct's, but the stored official NAV is still 28 Oct's.
        let data = try dataset(now: ist(2026, 10, 30, 11, 30))
        let e = try #require(Analytics.watched(data).first?.estimate)
        #expect(e.status == .notEstimable("Official NAV for 29 Oct 2026 isn't published yet"))
        #expect(e.estimatedNAV == nil)
    }
}

@Suite struct NiftyListTests {
    @Test func readsConstituentsByHeader() {
        let text = """
        Company Name,Industry,Symbol,Series,ISIN Code
        Adani Ports and Special Economic Zone Ltd.,Services,ADANIPORTS,EQ,INE742F01042
        "Bajaj Finance Ltd.",Financial Services,BAJFINANCE,EQ,INE296A01032
        Broken row,Services,,EQ,INE000000000
        """
        let stocks = NSESymbols.constituents(text)
        #expect(stocks.map(\.symbol) == ["ADANIPORTS", "BAJFINANCE"])
        #expect(stocks.first?.name == "Adani Ports and Special Economic Zone Ltd.")
        #expect(stocks.last?.industry == "Financial Services")
        #expect(NSESymbols.parse(text)["INE296A01032"] == "BAJFINANCE")
    }

    @Test func indexQuoteParsesUnderItsOwnKey() throws {
        let json = #"{"status":"success","data":{"NSE:NIFTY 50":{"last_price":24500.5,"ohlc":{"close":24400},"timestamp":"2026-10-30 10:00:00"}}}"#
        let q = try Kite.parseQuotes(Data(json.utf8), status: 200, symbolToISIN: [Kite.nifty50: "NIFTY 50"], fallbackTime: .now)
        #expect(q["NIFTY 50"]?.price == Decimal(string: "24500.5"))
        #expect(q["NIFTY 50"]?.previousClose == 24400)
    }
}
