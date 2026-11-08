# 03 — Architecture

## Layers

```
┌──────────────────────────────────────────────────────────────┐
│  App target (SwiftUI)                                        │
│  Views ─► Feature models (@Observable, @MainActor)            │
│  DesignSystem (tokens, components)                           │
└──────────────┬───────────────────────────────────────────────┘
               │ calls services, reads SwiftData via @Query
┌──────────────▼───────────────────────────────────────────────┐
│  FundScopeCore (no SwiftUI)                                  │
│  Services:  ImportService · SyncService · LiveNAVService     │
│             ReconciliationService · AlertService             │
│  Engine:    NAVEstimator · XIRR · LookThrough · DisclosureDiff│
│  Import:    CSVReader · XLSXReader · ColumnMapper · Validator │
│  Providers: protocols + adapters (Zerodha, AMFI, AMC, Mock)  │
│  Models:    SwiftData @Model types                           │
└──────────────┬───────────────────────────────────────────────┘
               │
        Network (URLSession, WebSocket) · Keychain · Files
```

Rules:
- Views never call a provider directly. They go through a service.
- The engine is pure functions on plain value types. No SwiftData, no network, no clock (the time is passed in). This keeps it easy to test.
- Providers only fetch and parse. They return value types, and services save them.

## Provider protocols

```swift
protocol PortfolioDataProvider: Sendable {
    func fetchHoldings(account: AccountID) async throws -> [HoldingRecord]
    func fetchTransactions(account: AccountID, since: Date?) async throws -> [TransactionRecord]
}

protocol OfficialNAVProvider: Sendable {
    func fetchSchemeDirectory() async throws -> [SchemeRecord]
    func fetchLatestNAVs() async throws -> [NAVRecord]
    func fetchNAVHistory(schemeCode: String, from: Date, to: Date) async throws -> [NAVRecord]
}

protocol FundHoldingsProvider: Sendable {
    func parseDisclosure(file: URL, mapping: DisclosureMapping?) throws -> DisclosureParseResult
}

protocol MarketDataProvider: Sendable {
    func quotes(for instruments: [InstrumentID]) async throws -> [QuoteRecord]
    func stream(_ instruments: [InstrumentID]) -> AsyncThrowingStream<QuoteRecord, Error>
    func history(_ instrument: InstrumentID, interval: CandleInterval, from: Date, to: Date) async throws -> [Candle]
}

protocol BenchmarkDataProvider: Sendable {
    func history(benchmark: BenchmarkID, from: Date, to: Date) async throws -> [BenchmarkPoint]
}
```

These are a sketch: method names will settle in Phase 1, but the split into five protocols stays.

| Protocol | Real adapters | Mock adapter |
|----------|--------------|--------------|
| PortfolioDataProvider | `ZerodhaFileImport` (CSV/XLSX), `KiteMFProvider` | `DemoPortfolioProvider` |
| OfficialNAVProvider | `AMFIProvider` | `FixtureNAVProvider` |
| FundHoldingsProvider | `AMCDisclosureParser` (one mapping per AMC) | `FixtureHoldingsProvider` |
| MarketDataProvider | `KiteMarketDataProvider` | `SimulatedMarketProvider` (random walk, clearly labelled) |
| BenchmarkDataProvider | none until a permitted source exists | `FixtureBenchmarkProvider` |

Mock providers are only compiled into Debug builds and demo mode. Real and demo data live in **separate SwiftData stores** (`FundScope.store` and `Demo.store`), so they can never mix.

**Read model.** Screens read a `Dataset` value (funds, disclosures, NAV history, quotes, transactions, reconciliations, source health) and compute figures through `Analytics` in Core. In Phase 1 `DemoData.make(now:)` builds the demo `Dataset` in memory; there's no demo store file yet. From Phase 2 the real store loads into the same `Dataset` shape, so screens don't change.

## Concurrency
- Swift 6 strict concurrency.
- UI-facing models are `@MainActor @Observable`.
- `LiveNAVService` is an `actor`. It owns the quote cache, receives ticks from the stream, recalculates estimates, and publishes snapshots to the main actor at most about once a second.
- SwiftData writes from background work use a `@ModelActor`.
- Network calls are `async`; cancel them when the view or task goes away.

## Data flow examples

**Import**
`fileImporter` → `ImportService.preview(file)` → reader → mapper → validator → `ImportPreview` (no writes) → user confirms → `ImportService.commit(preview)` in one transaction → `ImportRecord` saved.

**Live NAV**
Market opens → `LiveNAVService` collects the instruments for tracked funds → `MarketDataProvider.stream` → quote cache → `NAVEstimator.estimate(fund, holdings, quotes, baseline)` → `EstimatedNAV` snapshot (1/min saved, in memory more often) → UI and menu bar.

**Reconciliation**
AMFI NAV fetch (evenings) → new `OfficialNAV` for date D → `ReconciliationService` finds the frozen end-of-day estimate for D → writes a `NAVReconciliation` row. The estimate itself is never edited.

## Scheduling (while the app is running)

| Job | When |
|-----|------|
| AMFI latest NAV | On launch; then every 30 min between 20:00 and 23:59 IST on trading days, until all tracked funds have date-D NAV |
| Kite token check | On launch and before each Kite call |
| Quote streaming | 09:15–15:30 IST on trading days, if connected |
| End-of-day estimate freeze | 15:35 IST |
| Kite MF holdings sync | On launch and on "Sync now", if connected |
| Instrument master refresh | Once per day before 09:15 |

Market calendar: weekends plus an NSE holiday list stored as a bundled JSON that is updated each year. If a holiday is missing from the list, the app sees no ticks and shows "Market closed / no data", which is safe.

## Error model
One `FundScopeError` enum in Core with cases such as `.authRequired`, `.network`, `.parse(file:row:reason)`, `.missingData(what)`, `.rateLimited`, `.unsupported(reason)`. Every case has a user-facing message and a recovery action (Retry, Reconnect, Map columns, Import file). Views show these through the shared `ErrorState` component.
