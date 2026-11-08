import AppKit
import FundScopeCore
import Foundation
import Observation
import SwiftData

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case watchlist, liveNAV, nifty, explorer, compare, holdings, changes, accuracy, alerts, dataSources
    var id: String { rawValue }

    var title: String {
        switch self {
        case .watchlist: "Watchlist"
        case .liveNAV: "Live NAV"
        case .nifty: "Nifty 50"
        case .explorer: "Fund Explorer"
        case .compare: "Compare Funds"
        case .holdings: "Holdings Analysis"
        case .changes: "Holdings Changes"
        case .accuracy: "NAV Accuracy"
        case .alerts: "Alerts"
        case .dataSources: "Data Sources"
        }
    }

    var symbol: String {
        switch self {
        case .watchlist: "star"
        case .liveNAV: "waveform.path.ecg"
        case .nifty: "building.columns"
        case .explorer: "magnifyingglass"
        case .compare: "chart.line.uptrend.xyaxis"
        case .holdings: "circle.hexagongrid"
        case .changes: "arrow.left.arrow.right"
        case .accuracy: "scope"
        case .alerts: "bell"
        case .dataSources: "externaldrive.connected.to.line.below"
        }
    }

    static let groups: [(title: String, items: [SidebarItem])] = [
        ("Funds", [.watchlist, .liveNAV]),
        ("Market", [.nifty]),
        ("Research", [.explorer, .compare, .holdings, .changes]),
        ("Monitoring", [.accuracy, .alerts]),
    ]
}

struct FundRoute: Hashable {
    enum Tab: String, CaseIterable { case today = "Today", history = "NAV history", holdings = "Holdings" }
    let fundCode: String
    var tab: FundRoute.Tab = .today
}

/// App-wide state. Real mode is a watchlist of fund names backed by AMFI; demo data is generated in memory.
@Observable
final class AppModel {
    enum DataMode: String { case demo, real }

    private static let modeKey = "dataMode"
    private static let onboardedKey = "onboarded"

    private(set) var mode: DataMode
    private(set) var data: Dataset?
    private(set) var watched: [WatchedFund] = []
    /// AMFI schemes by code, and as a list for search.
    private(set) var directory: [String: SchemeRecord] = [:]
    private(set) var schemes: [SchemeRecord] = []
    private(set) var amfiFetchedAt: Date?
    private(set) var amfiError: String?
    private(set) var isRefreshingAMFI = false
    /// Set while NAV history downloads: finished and total requests.
    private(set) var historyProgress: (done: Int, total: Int)?
    private(set) var historyError: String?
    private var historyTask: Task<Void, Never>?
    /// True when a saved AMFI file is loaded for tests; nothing touches the network.
    private var isOffline = false

    // MARK: Kite state
    enum KiteState: Equatable {
        case notConfigured, disconnected, waitingForLogin, connected, authRequired, failed(String)
    }
    private(set) var kiteState: KiteState = .notConfigured
    private(set) var quotes: [String: Quote] = [:]
    private(set) var quotesFetchedAt: Date?
    private(set) var quoteError: String?
    /// ISIN → NSE symbol, from NSE's public equity list.
    private var nseSymbols: [String: String] = [:]
    private(set) var niftyStocks: [NSESymbols.IndexStock] = []
    /// Keyed by NSE symbol; the index itself is under "NIFTY 50".
    private(set) var niftyQuotes: [String: Quote] = [:]
    private(set) var niftyFetchedAt: Date?
    private var niftyError: String?
    /// Prices sampled through today's session for the intraday chart.
    private var samples: [(time: Date, prices: [String: Decimal])] = []
    private var pendingLoginState: String?
    private var quoteLoop: Task<Void, Never>?
    /// End-of-day estimates saved so far; never edited after saving.
    private(set) var frozen: [FrozenEstimate] = []
    let keychain: Keychain
    private(set) var storeError: String?
    /// Imported AMC disclosures per fund. Kept in memory only when the store is in memory (tests).
    private(set) var disclosures: [String: [Disclosure]] = [:]
    let container: ModelContainer?
    private let storeDirectory: URL?

    var selection: SidebarItem? = .watchlist {
        didSet { if oldValue != selection { path = [] } }
    }
    var path: [FundRoute] = []
    var showOnboarding = false
    var showAddFunds = false
    var showImportHoldings = false
    var showInspector = false
    var inspectedFund: String?

    init() {
        // `-storeInMemory YES` gives UI tests a clean store that never touches real data.
        let inMemory = UserDefaults.standard.bool(forKey: "storeInMemory")
        var directory: URL?
        var container: ModelContainer?
        var openError: String?
        do {
            if !inMemory {
                directory = try WatchlistStore.defaultDirectory()
                WatchlistStore.removeLegacyStore(in: directory!)
            }
            container = try WatchlistStore.container(directory: directory)
        } catch {
            openError = "FundScope couldn't open its local database: \(error.localizedDescription)"
        }
        self.container = container
        storeDirectory = directory
        storeError = openError
        // Tests never touch the real Kite credentials.
        // Keyed by bundle ID so a test copy of a family build never touches the real Kite items.
        keychain = Keychain(service: inMemory ? "com.vikasghodke.FundScope.kite.uitest" : (Bundle.main.bundleIdentifier ?? "com.vikasghodke.FundScope") + ".kite")
        // `-dataMode demo` as a launch argument overrides the stored choice (used by UI tests).
        mode = UserDefaults.standard.string(forKey: Self.modeKey) == DataMode.demo.rawValue ? .demo : .real
        showOnboarding = !UserDefaults.standard.bool(forKey: Self.onboardedKey) && storeError == nil

        #if DEBUG
        // `-section nifty` opens a sidebar section at launch (checks and UI tests).
        if let section = UserDefaults.standard.string(forKey: "section").flatMap(SidebarItem.init(rawValue:)) { selection = section }
        // UI tests load a saved AMFI file instead of the network.
        if let path = UserDefaults.standard.string(forKey: "amfiFixture"), let text = try? String(contentsOfFile: path, encoding: .utf8) {
            applyDirectory(AMFI.parse(text), fetchedAt: .now)
            isOffline = true
            reload()
            return
        }
        #endif
        let starter = Bundle.main.url(forResource: "StarterFunds", withExtension: "json")
        if let directory, starter != nil, WatchlistStore.cachedAMFI(in: directory) == nil,
           let navs = Bundle.main.url(forResource: "NAVAll", withExtension: "txt") {
            // The bundled copy keeps its old date, so the refresh below replaces it as soon as AMFI answers.
            try? FileManager.default.copyItem(at: navs, to: directory.appending(path: "NAVAll.txt"))
        }
        if let directory, let cached = WatchlistStore.cachedAMFI(in: directory) {
            applyDirectory(AMFI.parse(cached.text), fetchedAt: cached.fetchedAt)
        }
        if let directory, let starter, showOnboarding { seedStarterFunds(from: starter, in: directory) }
        updateKiteState()
        for url in NSESymbols.urls {
            if let directory, let cached = try? String(contentsOf: directory.appending(path: url.lastPathComponent), encoding: .utf8) {
                applySymbolList(cached, from: url)
            }
        }
        if let directory { frozen = EstimateStore.load(in: directory) }
        startQuoteLoop()
        reload()
        if (amfiFetchedAt.map { Date.now.timeIntervalSince($0) > 6 * 3600 } ?? true) {
            Task { await refreshAMFI() }
        } else {
            backfillHistory()
        }
    }

    // MARK: Data

    func reload() {
        switch mode {
        case .demo:
            data = DemoData.make()
        case .real:
            guard let container else { data = nil; break }
            if let storeDirectory {
                let codes = Set(((try? WatchlistStore.items(container.mainContext)) ?? []).map(\.code))
                disclosures = DisclosureStore.load(codes: codes, in: storeDirectory)
            }
            let sessionDay = MarketCalendar().sessionDay(at: .now)
            let today = samples.filter { MarketCalendar().calendar.isDate($0.time, inSameDayAs: sessionDay) }
            var samplePrices: [String: [Decimal]] = [:]
            for isin in quotes.keys {
                // Carry the last known price forward when a sample missed a stock.
                var last: Decimal?
                samplePrices[isin] = today.compactMap { s in last = s.prices[isin] ?? last; return last }
                if samplePrices[isin]?.count != today.count { samplePrices[isin] = nil }
            }
            data = try? WatchlistStore.dataset(
                container.mainContext, directory: directory,
                amfi: .init(fetchedAt: amfiFetchedAt, error: amfiError, schemeCount: schemes.count),
                disclosures: disclosures,
                market: .init(quotes: quotes, sampleTimes: today.map(\.time), samplePrices: samplePrices, health: kiteHealth),
                frozen: frozen, now: .now)
        }
        watched = data.map(Analytics.watched) ?? []
    }

    /// Downloads AMFI's NAV file, caches it, and records today's NAV for watched funds.
    func refreshAMFI() async {
        guard !isRefreshingAMFI else { return }
        isRefreshingAMFI = true
        defer { isRefreshingAMFI = false }
        do {
            let text = try await AMFI.download()
            let records = await Task.detached { AMFI.parse(text) }.value
            if let storeDirectory { try? WatchlistStore.cacheAMFI(text, in: storeDirectory) }
            amfiError = nil
            applyDirectory(records, fetchedAt: .now)
            if let container {
                let context = container.mainContext
                let watchedCodes = Set(((try? WatchlistStore.items(context)) ?? []).map(\.code))
                try WatchlistStore.recordNAVs(records.filter { watchedCodes.contains($0.code) }, now: .now, context: context)
                try context.save()
            }
        } catch {
            amfiError = error.localizedDescription
        }
        reload()
        backfillHistory()
    }

    /// Downloads missing NAV history for watched funds in the background (up to 5 years, 3 requests at a time).
    func backfillHistory() {
        guard mode == .real, !isOffline, historyTask == nil, let container else { return }
        historyTask = Task {
            await runBackfill(container.mainContext)
            historyTask = nil
        }
    }

    private struct HistoryJob: Sendable {
        let code: String
        let from: Date
        let to: Date
    }

    private enum HistoryResult: Sendable {
        case success(String, [NAVPoint])
        case failure(String, String)
    }

    /// How far back each fund's history has been checked, so funds younger than 5 years
    /// aren't asked again for years before they existed.
    private static let coveredKey = "historyCoveredFrom"
    private var historyCoveredFrom: [String: Date] {
        get { UserDefaults.standard.dictionary(forKey: Self.coveredKey) as? [String: Date] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.coveredKey) }
    }

    private func runBackfill(_ context: ModelContext) async {
        let codes = ((try? WatchlistStore.items(context)) ?? []).map(\.code)
        let covered = historyCoveredFrom
        let jobs = codes.flatMap { code in
            let span = try? WatchlistStore.historySpan(code: code, context: context)
            let earliest = [span?.earliest, covered[code]].compactMap { $0 }.min()
            return AMFIHistory.missingRanges(earliest: span == nil ? nil : earliest, latest: span?.latest, today: .now)
                .map { HistoryJob(code: code, from: $0.from, to: $0.to) }
        }
        guard !jobs.isEmpty else { return }
        historyProgress = (0, jobs.count)
        historyError = nil
        var failedCodes: Set<String> = []
        var failed = 0
        await withTaskGroup(of: HistoryResult.self) { group in
            var pending = jobs[...]
            func start(_ job: HistoryJob) {
                group.addTask {
                    do { return .success(job.code, try await AMFIHistory.fetch(code: job.code, from: job.from, to: job.to)) }
                    catch { return .failure(job.code, error.localizedDescription) }
                }
            }
            // Be gentle with AMFI's server: at most 3 requests in flight.
            for _ in 0..<3 { if let job = pending.popFirst() { start(job) } }
            for await result in group {
                switch result {
                case .success(let code, let points):
                    _ = try? WatchlistStore.recordHistory(code: code, points: points, now: .now, context: context)
                case .failure(let code, let message):
                    failedCodes.insert(code)
                    failed += 1
                    historyError = message
                }
                historyProgress = historyProgress.map { ($0.done + 1, $0.total) }
                reload()
                if let job = pending.popFirst() { start(job) }
            }
        }
        var newlyCovered = historyCoveredFrom
        for (code, codeJobs) in Dictionary(grouping: jobs, by: \.code) where !failedCodes.contains(code) {
            if let from = codeJobs.map(\.from).min() { newlyCovered[code] = min(from, newlyCovered[code] ?? from) }
        }
        historyCoveredFrom = newlyCovered
        if failed > 0 { historyError = "\(failed) of \(jobs.count) history downloads failed (\(historyError ?? "unknown error")). They'll be retried next time." }
        historyProgress = nil
        reload()
    }

    private func applyDirectory(_ records: [SchemeRecord], fetchedAt: Date) {
        schemes = records
        directory = Dictionary(records.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        amfiFetchedAt = fetchedAt
    }

    // MARK: Watchlist

    func isWatched(_ code: String) -> Bool { mode == .real && watched.contains { $0.fund.code == code } }

    @discardableResult
    func add(_ schemes: [SchemeRecord]) throws -> Int {
        guard let container else { return 0 }
        let added = try WatchlistStore.add(schemes, now: .now, context: container.mainContext)
        if mode == .demo { mode = .real; UserDefaults.standard.set(DataMode.real.rawValue, forKey: Self.modeKey) }
        finishOnboarding()
        reload()
        backfillHistory()
        Task { await refreshQuotes() }
        return added
    }

    /// Family builds (scripts/make-family-build.sh) carry a watchlist and its holdings, so a new Mac starts with them.
    private func seedStarterFunds(from url: URL, in directory: URL) {
        guard let container, (try? WatchlistStore.items(container.mainContext))?.isEmpty == true else { return }
        do {
            let codes = try DisclosureStore.seed(from: url, in: directory)
            let found = codes.compactMap { self.directory[$0] }
            try WatchlistStore.add(found, now: .now, context: container.mainContext)
            if found.count < codes.count {
                amfiError = "\(codes.count - found.count) of the bundled funds aren't in AMFI's scheme list. Add them from Add Funds."
            }
            finishOnboarding()
            showOnboarding = false
        } catch {
            storeError = "FundScope couldn't load its bundled funds: \(error.localizedDescription)"
        }
    }

    func remove(_ code: String) {
        guard let container, mode == .real else { return }
        try? WatchlistStore.remove(code: code, context: container.mainContext)
        historyCoveredFrom[code] = nil
        if inspectedFund == code { inspectedFund = nil }
        reload()
    }

    // MARK: Holdings

    /// Saves a parsed disclosure for a watched fund. A month that's already saved is kept as it was.
    func saveDisclosure(_ parsed: DisclosureParser.Parsed, fundCode: String, fileName: String) throws -> DisclosureStore.SaveResult {
        guard let date = parsed.date else { throw CocoaError(.fileReadCorruptFile) }
        let disclosure = Disclosure(fundCode: fundCode, disclosureDate: date, holdings: parsed.holdings,
                                    sourceTitle: parsed.title, sourceFile: fileName, importedAt: .now)
        let result: DisclosureStore.SaveResult
        if let storeDirectory {
            result = try DisclosureStore.save(disclosure, in: storeDirectory)
        } else if disclosures[fundCode]?.contains(where: { $0.disclosureDate == date }) == true {
            result = .alreadyHave
        } else {
            disclosures[fundCode, default: []].append(disclosure)
            disclosures[fundCode]?.sort { $0.disclosureDate < $1.disclosureDate }
            result = .saved
        }
        reload()
        if result == .saved { Task { await refreshQuotes() } }
        return result
    }

    func hasDisclosure(_ code: String, date: Date?) -> Bool {
        guard let date else { return false }
        return disclosures[code]?.contains { $0.disclosureDate == date } == true
    }

    // MARK: Kite Connect

    var kiteAPIKey: String? { keychain.get(.apiKey) }

    private func updateKiteState() {
        if keychain.get(.apiKey) == nil || keychain.get(.apiSecret) == nil { kiteState = .notConfigured }
        else if keychain.get(.accessToken) == nil { if kiteState != .authRequired { kiteState = .disconnected } }
        else { kiteState = .connected }
    }

    /// Saves the user's own Kite app key and secret in the Keychain. Changing them ends the current session.
    func saveKiteCredentials(apiKey: String, apiSecret: String) throws {
        try keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: .apiKey)
        try keychain.set(apiSecret.trimmingCharacters(in: .whitespacesAndNewlines), for: .apiSecret)
        try keychain.delete(.accessToken)
        updateKiteState()
    }

    /// Opens Zerodha's login page in the browser and waits for its redirect on 127.0.0.1.
    func connectKite() async {
        guard let apiKey = keychain.get(.apiKey) else { return }
        let state = UUID().uuidString
        pendingLoginState = state
        kiteState = .waitingForLogin
        NSWorkspace.shared.open(Kite.loginURL(apiKey: apiKey, state: state))
        do {
            let redirect = try await LoginCallback.wait()
            try await completeKiteLogin(redirect: redirect)
        } catch {
            if kiteState == .waitingForLogin { kiteState = .failed(error.localizedDescription) }
        }
    }

    /// Finishes login from the redirect URL (caught automatically, or pasted from the browser's address bar).
    func completeKiteLogin(redirect: URL) async throws {
        guard let state = pendingLoginState, let apiKey = keychain.get(.apiKey), let secret = keychain.get(.apiSecret) else {
            throw Kite.KiteError.loginRejected("start the login from FundScope first")
        }
        let token = try Kite.requestToken(fromRedirect: redirect, expectedState: state)
        let session = try await Kite.createSession(apiKey: apiKey, requestToken: token, apiSecret: secret)
        try keychain.set(session.access_token, for: .accessToken)
        pendingLoginState = nil
        UserDefaults.standard.set(Date.now, forKey: "kiteConnectedAt")
        kiteState = .connected
        await refreshQuotes()
    }

    func disconnectKite() async {
        if let key = keychain.get(.apiKey), let token = keychain.get(.accessToken) {
            try? await Kite.logout(apiKey: key, accessToken: token)
        }
        try? keychain.delete(.accessToken)
        quotes = [:]
        samples = []
        updateKiteState()
        reload()
    }

    /// Ends the Kite session (while the key still exists to do so), then removes key and secret.
    func forgetKiteCredentials() async {
        await disconnectKite()
        Keychain.Item.allCases.forEach { try? keychain.delete($0) }
        updateKiteState()
    }

    var kiteConnectedAt: Date? { UserDefaults.standard.object(forKey: "kiteConnectedAt") as? Date }

    /// NSE symbols for every listed stock and ETF in the latest holdings of watched funds.
    private func symbolsToQuote() async -> [String: String] {
        if nseSymbols.isEmpty || isSymbolListStale { await refreshSymbolLists() }
        let isins = Set(disclosures.values.compactMap(\.last).flatMap(\.holdings)
            .filter { !$0.assetType.isFlatResidual }.compactMap(\.security?.isin))
        return Dictionary(isins.compactMap { isin in nseSymbols[isin].map { ("NSE:\($0)", isin) } }, uniquingKeysWith: { a, _ in a })
    }

    private func refreshSymbolLists() async {
        for url in NSESymbols.urls {
            guard let text = try? await NSESymbols.download(url) else { continue }
            applySymbolList(text, from: url)
            if let storeDirectory { try? text.write(to: storeDirectory.appending(path: url.lastPathComponent), atomically: true, encoding: .utf8) }
        }
    }

    private func applySymbolList(_ text: String, from url: URL) {
        nseSymbols.merge(NSESymbols.parse(text)) { _, new in new }
        if url == NSESymbols.niftyFiftyURL { niftyStocks = NSESymbols.constituents(text) }
    }

    // MARK: Nifty 50

    /// Keeps Nifty prices current while the Nifty page is open (the view's task cancels it):
    /// every 2 seconds in market hours, once a minute otherwise. Kite allows 1 quote request a second.
    func streamNifty() async {
        while !Task.isCancelled {
            await refreshNifty()
            try? await Task.sleep(for: .seconds(MarketCalendar().status(at: .now) == .open ? 2 : 60))
        }
    }

    private func refreshNifty() async {
        if niftyStocks.isEmpty || isSymbolListStale { await refreshSymbolLists() }
        guard !isOffline, kiteState == .connected, !niftyStocks.isEmpty,
              let key = keychain.get(.apiKey), let token = keychain.get(.accessToken) else { return }
        var symbols = Dictionary(niftyStocks.map { ("NSE:\($0.symbol)", $0.symbol) }, uniquingKeysWith: { a, _ in a })
        symbols[Kite.nifty50] = "NIFTY 50"
        do {
            niftyQuotes = try await Kite.quotes(symbolToISIN: symbols, apiKey: key, accessToken: token)
            niftyFetchedAt = .now
            niftyError = nil
        } catch Kite.KiteError.authRequired {
            try? keychain.delete(.accessToken)
            kiteState = .authRequired
        } catch {
            // Keep the last prices; an occasional clash with the fund quote loop isn't worth a warning.
            niftyError = error.localizedDescription
        }
    }

    /// A fetch problem worth showing: the last good prices are more than 10 seconds old.
    var niftyProblem: String? {
        guard let niftyError, (niftyFetchedAt.map { Date.now.timeIntervalSince($0) > 10 } ?? true) else { return nil }
        return niftyError
    }

    /// True when any NSE list is missing or older than a week.
    private var isSymbolListStale: Bool {
        guard let dir = storeDirectory else { return true }
        return NSESymbols.urls.contains { url in
            let path = dir.appending(path: url.lastPathComponent).path(percentEncoded: false)
            guard let date = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date else { return true }
            return Date.now.timeIntervalSince(date) > 7 * 86_400
        }
    }

    /// Fetches live prices for the watched funds' stocks. An expired session switches to "Requires authentication".
    func refreshQuotes() async {
        guard mode == .real, !isOffline, kiteState == .connected,
              let key = keychain.get(.apiKey), let token = keychain.get(.accessToken) else { return }
        let symbols = await symbolsToQuote()
        guard !symbols.isEmpty else { return }
        do {
            let fresh = try await Kite.quotes(symbolToISIN: symbols, apiKey: key, accessToken: token)
            quotes = fresh
            quotesFetchedAt = .now
            quoteError = nil
            if MarketCalendar().status(at: .now) == .open {
                samples.append((.now, fresh.mapValues(\.price)))
            }
            reload()
            freezeIfSessionClosed()
        } catch Kite.KiteError.authRequired {
            try? keychain.delete(.accessToken)
            kiteState = .authRequired
            quoteError = Kite.KiteError.authRequired.localizedDescription
        } catch {
            // Keep the last prices with their timestamps rather than showing nothing.
            quoteError = error.localizedDescription
        }
        reload()
    }

    private var frozenToday: Bool {
        frozen.contains { MarketCalendar().calendar.isDate($0.valuationDate, inSameDayAs: .now) }
    }

    /// Saves today's final estimates once the session has closed and closing prices are in.
    private func freezeIfSessionClosed() {
        let calendar = MarketCalendar()
        guard let data, !data.isDemo,
              Reconciler.shouldFreeze(now: .now, latestQuoteTime: quotes.values.map(\.exchangeTime).max(),
                                      alreadyFrozenToday: frozenToday, calendar: calendar) else { return }
        let estimates = Reconciler.freeze(data, now: .now)
        guard !estimates.isEmpty else { return }
        if let storeDirectory {
            do { try EstimateStore.save(estimates, day: data.sessionDay, in: storeDirectory) }
            catch { quoteError = "Couldn't save today's end-of-day estimates: \(error.localizedDescription)" }
        }
        frozen += estimates
        reload()
    }

    /// Estimates saved but still waiting for AMFI's official NAV.
    var pendingReconciliations: [FrozenEstimate] {
        let reconciled = Set((data?.reconciliations ?? []).map { "\($0.fundCode)|\($0.valuationDate.timeIntervalSince1970)" })
        return frozen.filter { !reconciled.contains("\($0.fundCode)|\($0.valuationDate.timeIntervalSince1970)") }
    }

    /// Refreshes prices once a minute while the market is open, and once at start-up for the last session.
    private func startQuoteLoop() {
        quoteLoop?.cancel()
        quoteLoop = Task { [weak self] in
            await self?.refreshQuotes()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                let calendar = MarketCalendar()
                let afterClose = calendar.isTradingDay(.now) && calendar.status(at: .now) == .closed
                    && calendar.calendar.component(.hour, from: .now) >= 15
                // During the session every minute; after the close, until the day's estimates are saved.
                if calendar.status(at: .now) == .open || (afterClose && self?.frozenToday == false) { await self?.refreshQuotes() }
            }
        }
    }

    private var kiteHealth: DataSourceHealth {
        let status: ProviderStatus, warning: String?
        switch kiteState {
        case .notConfigured: (status, warning) = (.authRequired, "Add your Kite Connect API key in Settings → Zerodha")
        case .disconnected, .waitingForLogin: (status, warning) = (.authRequired, "Connect in Settings → Zerodha")
        case .authRequired: (status, warning) = (.authRequired, "Session expired (Kite sessions end at 6 AM). Reconnect in Settings → Zerodha")
        case .failed(let message): (status, warning) = (.unavailable, message)
        case .connected:
            let stale = quotesFetchedAt.map { Date.now.timeIntervalSince($0) > 300 } ?? true
            status = quoteError != nil ? .stale : (stale && MarketCalendar().status(at: .now) == .open ? .stale : .connected)
            warning = quoteError
        }
        return DataSourceHealth(name: "Zerodha Kite Connect", detail: "Live stock prices only, no account data", status: status,
                                lastSuccess: quotesFetchedAt, latestDataDate: quotes.values.map(\.exchangeTime).max(),
                                records: quotes.isEmpty ? nil : quotes.count, warning: warning)
    }

    // MARK: Modes

    func enterDemo() {
        mode = .demo
        UserDefaults.standard.set(DataMode.demo.rawValue, forKey: Self.modeKey)
        finishOnboarding()
        reload()
    }

    func exitDemo() {
        mode = .real
        UserDefaults.standard.set(DataMode.real.rawValue, forKey: Self.modeKey)
        selection = .watchlist
        reload()
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
    }

    // MARK: Helpers

    var marketStatus: MarketStatus {
        (data?.calendar ?? MarketCalendar()).status(at: data?.now ?? .now)
    }

    /// Source label for live figures: estimated during the session, "last session" afterwards.
    var liveSource: FigureSource {
        guard let data else { return .estimated(nil) }
        return data.sessionIsLive ? .estimated(data.asOf) : .previousSession(data.sessionDay)
    }

    func fund(_ code: String) -> FundInfo? { data?.funds.first { $0.code == code } ?? directory[code]?.fundInfo }

    func open(_ code: String, tab: FundRoute.Tab = .today) {
        path.append(FundRoute(fundCode: code, tab: tab))
    }

    func inspect(_ code: String?) {
        inspectedFund = code
    }
}
