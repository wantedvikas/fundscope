# FundScope — Roadmap

FundScope is a native macOS app (SwiftUI, macOS 15+) for tracking personal Indian mutual fund investments held through Zerodha Coin. It runs only on your Mac, with no accounts, servers or subscriptions.

This file gives the order of work. Each phase links to the docs that describe it in detail.

## Document index

| # | Document | What it covers |
|---|----------|----------------|
| 00 | [AGENTS.md](AGENTS.md) | Permanent engineering rules for anyone (human or AI) working on the code |
| 01 | [Product requirements](docs/01-product-requirements.md) | What the app must do, scope, definition of done, decisions |
| 02 | [Tech stack](docs/02-tech-stack.md) | Languages, frameworks, dependencies, toolchain |
| 03 | [Architecture](docs/03-architecture.md) | Modules, layers, provider protocols, concurrency |
| 04 | [Design system](docs/04-design-system.md) | Tokens, typography, color, components, states |
| 05 | [App flow](docs/05-app-flow.md) | Onboarding, navigation, user journeys |
| 06 | [Screens](docs/06-screens.md) | Each screen's content, layout and states |
| 07 | [Data model](docs/07-data-model.md) | Entities, identifiers, precision, migrations |
| 08 | [Data sources](docs/08-data-sources.md) | Zerodha Kite Connect, AMFI, AMC disclosures, benchmarks |
| 09 | [Import](docs/09-import.md) | Zerodha Coin/Console CSV and XLSX import pipeline |
| 10 | [NAV engine](docs/10-nav-engine.md) | Estimated NAV, reconciliation, accuracy, XIRR, look-through |
| 11 | [Security & privacy](docs/11-security-privacy.md) | Keychain, secrets, what each provider sees |
| 12 | [Testing](docs/12-testing.md) | Test plan, fixtures, build verification |

## Phases

Each phase ends with: the app builds, all tests pass, light and dark mode have been checked, and a phase report is written (see "Phase report" below). A phase is not done until its exit criteria are verified in the running app.

### Phase 0 — Decisions and setup (before any code)
- ✅ Decisions recorded in [01 §Decisions](docs/01-product-requirements.md#decisions).
- Collect real samples: one Zerodha Coin holdings export, one Console tradebook/MF transaction export, and the latest monthly portfolio XLSX from PPFAS, HDFC and ICICI Prudential. Strip personal identifiers, then save them as test fixtures.
- Check current Kite Connect pricing, market-data and index-quote entitlements, then subscribe (see [08](docs/08-data-sources.md)).

**Exit:** sample files in `Fixtures/`; Kite plan details confirmed in [08](docs/08-data-sources.md).

### Phase 1 — Architecture and design system ✅ ([report](docs/reports/phase-1.md))
- Create the Xcode project (app target, `FundScopeCore` Swift package, test targets).
- Commit `AGENTS.md` and these docs.
- Build design tokens and shared components ([04](docs/04-design-system.md)).
- Build the `NavigationSplitView` shell with every sidebar section.
- Build every primary screen using **demo data**, clearly labelled with a "Demo" badge.
- Check light and dark mode, and window resizing.

**Exit:** every screen is reachable, uses only shared components, and shows the demo badge. Builds with no warnings.

### Phase 2 — Watchlist and AMFI ✅ ([report](docs/reports/phase-2.md))
Replaced the Zerodha import (decision D7: no personal amounts).
- AMFI scheme list and daily official NAV, cached and refreshed.
- Add funds by search, pasted names, or the name column of a holdings file.
- Watchlist screen; Fund Explorer over all AMFI schemes; equal-weight composition.
- NAV history saved daily from now on.

**Exit:** a list of fund names matches their AMFI Direct Growth schemes and show today's official NAV. ✅ (Verified in tests; check on your Mac.)

### Phase 3 — NAV history and fund holdings
- ✅ Historical NAV backfill: 5 years per fund from AMFI's NAV history API ([report](docs/reports/phase-3a-nav-history.md)).
- ✅ AMC monthly holdings import (manual file, any layout with ISIN and % columns) ([report](docs/reports/phase-3b-holdings.md)).
- AMC portfolio disclosure importer (one AMC first, then a reusable mapping).
- Security master (ISIN to company, sector, market-cap bucket).
- Fund Explorer and fund detail with holdings.
- Data Sources health screen.

**Exit:** official NAV and official portfolio value are correct for every imported fund; opening a fund shows its disclosed holdings with the disclosure date.

### Phase 4 — Live market data ✅ verified with a real Kite Connect app ([report](docs/reports/phase-4-kite.md))
- Kite Connect module: login flow, Keychain storage, token expiry, reconnect.
- Instrument master download, mapping ISIN to instrument token.
- REST quotes, then WebSocket streaming, reconnect handling and stale-quote detection.
- MF holdings sync from Kite (if your plan allows it).
- Zerodha settings screen.

**Exit:** during market hours, live prices for underlying stocks update in the app; after the token expires, the app shows "Requires authentication" and reconnecting works.

### Phase 5 — Estimated live NAV
- Pure calculation engine in `FundScopeCore` ([10](docs/10-nav-engine.md)).
- Intraday snapshots, live NAV chart, contribution breakdown.
- Coverage, freshness and unsupported-fund warnings.

**Exit:** engine tests pass on hand-computed fixtures; Live NAV screen shows estimates with coverage visible.

### Phase 6 — NAV accuracy 🟡 built, waiting for a real trading day ([report](docs/reports/phase-6-accuracy.md))
- Freeze an end-of-day estimate per fund per valuation date.
- Reconcile against official NAV when it arrives.
- Accuracy analytics (mean, median and worst absolute % error, trend).

**Exit:** after at least one real trading day, a reconciliation row exists and the original estimate is unchanged.

### Phase 7 — Advanced analytics
- Look-through exposure (stocks, sectors, market cap), overlap, concentration.
- Portfolio value history adjusted for cash flows; XIRR per fund, account and portfolio.
- Monthly disclosure diff.
- Fund and benchmark comparison.
- Combined family view.

**Exit:** exposure totals add up to 100% including explicit "Unmapped" and "Unsupported" buckets; XIRR matches a spreadsheet `XIRR()` on fixtures.

### Phase 8 — macOS polish
- MenuBarExtra tracker.
- Local notifications and alert rules.
- Keyboard shortcuts, saved window state, accessibility (VoiceOver labels, keyboard navigation).
- Performance pass (large tables, streaming updates).
- Final visual consistency review against [04](docs/04-design-system.md).
- Family install without a paid developer account: ad-hoc signed Release zip, then on one family Mac approve it with Open Anyway, run onboarding with that person's own Kite credentials, and check that an update keeps their data and handles the Keychain prompt.

**Exit:** every item in the [definition of done](docs/01-product-requirements.md#definition-of-done) is verified with real data.

## Dependency graph

```
Phase 1 ──► Phase 2 ──► Phase 3 ──┬──► Phase 5 ──► Phase 6
                                  │        ▲
                      Phase 4 ────┘────────┘
                                  └──► Phase 7 ──► Phase 8
```

Phase 4 (Kite) can start alongside Phase 3 once the Phase 1 shell exists, but it needs credentials. Without them, Phase 5 runs on a clearly separated mock market data provider.

## Phase report template

```
## Phase N report — <date>
Implemented:
Files created/changed:
Tests run: <command> → <pass/fail counts>
Build: <scheme, configuration, result, warnings>
Verified in app: <what was checked by hand>
Known limitations:
Next steps:
```
