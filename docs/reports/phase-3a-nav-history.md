# Phase 3a report — NAV history — 2026-10-29

## Implemented
- **`AMFIHistory`** (Core):
  - Per-scheme history from AMFI's NAV History API (verified format, limits and error shapes).
  - NAVs are decoded as exact decimals.
  - `missingRanges` works out what's missing: up to 5 years in ≤3-year chunks, newest first, plus any gap since the app was last opened. It skips today, which the daily file already covers.
- **Storage:** `WatchlistStore.recordHistory` (insert-only, existing dates untouched) and `historySpan`.
- **App backfill:**
  - Runs after AMFI refreshes and after adding funds, in the background, 3 requests at a time.
  - Progress shows in the Watchlist subtitle; failures show a warning and are retried next time.
  - Remembers how far back each fund has been checked, so young funds aren't asked again for dates before they existed.
- **Screens:** Watchlist gained **1M** and **1Y** return columns, and the 1-day change now works. Fund detail → NAV history and Compare Funds (charts and trailing returns) use the real history. Compare hides the benchmark until Kite Connect supplies one.
- **Privacy fixes:**
  - The scheme no longer keeps Xcode's automatic screenshots or recordings, and test result bundles were deleted.
  - The live UI test was replaced with a windowless live check.
  - Offline UI tests can no longer reach the network.

## Tests run
- `swift test` → **46 passed**. New tests cover parsing a real 3-year response exactly, "no records" vs error, URL format, chunking under the limit, gap-only and already-checked cases, and history stored once then turned into a 1-day change.
- **Live check** (`FUNDSCOPE_LIVE=1 … --filter LiveAMFI`) → passed. All 14 test funds downloaded:
  - 11 funds: about 1,230 NAVs each, from 1 Nov 2021 to 28 Oct 2026.
  - WhiteOak Mid Cap: from Sep 2022. WhiteOak Flexi Cap: from Aug 2022. Abakkus Small Cap: from Mar 2026 (their launch dates).
  - No overlapping days. Took 137 s.
- Build: 0 errors, 0 warnings.
- `xcodebuild -scheme FundScope -only-testing:FundScopeUITests test` → **5 passed** (run while the Mac was free). Fixes found on the way:
  - Tests now launch with `-ApplePersistenceIgnoreState YES`. Without it, macOS restored a "no windows" state left by a manual run.
  - "Add Funds…" moved from ⌘N to ⇧⌘N, so it no longer clashes with New Window.
  - Watchlist columns were tightened (NAV date moved into the Official NAV hover) so the table fits without scrolling sideways.

## Known limitations
- The history API is undocumented (it's what AMFI's own page uses) and could change without notice.
- History requests reveal to AMFI which scheme codes are being looked up. No amounts or identity are sent.
- The first backfill takes about 2–3 minutes for 14 funds, because AMFI's server is slow.

## Next steps
1. AMC monthly holdings import (PPFAS, HDFC, ICICI Prudential first).
