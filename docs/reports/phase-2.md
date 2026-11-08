# Phase 2 report — Watchlist and AMFI — 2026-10-29

Replaces the earlier Zerodha-import Phase 2, which was removed at the owner's request: FundScope must not store what was invested.

## Implemented
- **Removed:** Coin/Console import, the column mapper, import history, transactions, units, invested amounts, P&L, XIRR, accounts and family portfolios (code, screens and tests). The old database file is deleted on launch.
- **AMFI** (`Providers/AMFI.swift`): downloads the public NAV file (verified URL and format), parses all ~14,400 schemes with AMC and category, caches it, and refreshes it when it's older than 6 hours or on ⌘R.
- **Fund matching** (`FundMatcher`): word matching with short forms (Pru, WOC, PPFAS, Smallcap…), ignoring "(erstwhile …)" notes. Defaults to Direct Growth. Only all-words matches are auto-selected; anything else asks you to pick.
- **File names only** (`FundListReader`): reads the fund-name and plan columns from a holdings CSV/XLSX and ignores everything else.
- **Watchlist store** (SwiftData V1): fund codes and daily official NAVs only. Adding is idempotent; removing deletes that fund's NAVs.
- **UI:**
  - Watchlist screen (official NAV and date, 1-day change, live-estimate status, equal-weight composition).
  - Add Funds sheet (search, or paste a list / drop a file, then confirm matches).
  - Onboarding: add funds or open demo.
  - Fund Explorer over all AMFI schemes, with right-click Add/Remove.
  - Holdings Analysis switched to equal weights; Data Sources shows real AMFI status.

## Tests run
- `swift test --package-path Packages/FundScopeCore` → **38 passed**, including:
  - Each of 14 sample fund names → the correct AMFI scheme code.
  - The AMFI parser (current and older layouts, N.A. NAVs).
  - The file reader on your file's layout, with all numbers zeroed.
  - Store behaviour; NAV history never overwritten; old database deleted.
- `xcodebuild -scheme FundScope test` → **5 UI tests passed**: smoke tests in light and dark mode, onboarding, fund detail, and adding 14 funds by name through onboarding.

## Build
Debug build: 0 errors, 0 warnings in FundScope code.

## Known limitations
- **1-day change shows "—"** until FundScope has saved two days of official NAVs (it starts saving from the first run). The historical backfill is next.
- **Live estimates** need each fund's monthly holdings disclosure (next) and live stock prices from Kite Connect (Phase 4).
- **Not estimable:** ICICI Pru Multi Asset Allocation and Invesco India Arbitrage, because they're hybrid funds. Parag Parikh Flexi Cap will probably be "Not estimable" once its disclosure is imported, because of its foreign holdings.
- **Typing in UI tests:** the test runner couldn't type on this Mac, so the add-funds UI test pre-fills names through a Debug-only launch argument. Search typing is covered by unit tests, not UI tests.
- The real AMFI download was tested by hand with curl. The app test uses a saved slice of it.

## Next steps
1. NAV history backfill from AMFI's history report, so Compare and the NAV charts work straight away.
2. AMC monthly holdings import (PPFAS, HDFC, ICICI Prudential first), which unlocks Holdings Analysis, overlap and the Holdings Changes screen for watched funds.
3. Kite Connect for live prices, then live NAV estimates.
