# Phase 6 report — NAV accuracy — 2026-10-29

## Implemented
- **`Reconciler`** (Core, pure):
  - `shouldFreeze` saves only after the close on a trading day, once, using quotes taken at or after 15:25 IST that same day. A machine that slept through the afternoon doesn't save an intraday number as the "close".
  - `freeze` covers estimable funds only.
  - `reconcile` matches each saved estimate to the official NAV for the same fund and day.
- **`EstimateStore`:** one write-once JSON file per trading day; a later run can't change it. Reconciliations are worked out from saved estimates plus official NAVs, never stored or edited.
- **App:**
  - After the close, the price loop keeps fetching until the day's estimates are saved, then stops until the next session.
  - AMFI's evening NAV, already fetched daily, completes the comparison automatically.
  - If saving fails, an error shows in Settings → Zerodha and Data Sources, so no estimate is lost silently.
- **NAV Accuracy screen:** reconciliations feed the existing chart, stats (mean, median, worst, within ±0.25%) and table. It shows "Waiting for official NAVs" with the count and date of estimates waiting, and tells you to keep FundScope open past 3:30 PM with Zerodha connected.

## Tests run
- `swift test` → **73 passed**. New tests:
  - freeze timing: after close yes; during market no; morning-only quotes no; yesterday's quotes no; weekend no; twice no;
  - reconcile only matching days (+0.2% error);
  - demo estimates freeze with model version and never for the liquid fund;
  - the store is write-once.
- Build: 0 errors, 0 warnings. UI tests not re-run (they need the Mac to be free). Demo NAV Accuracy is unchanged.

## Not verified yet
A real freeze and reconciliation. It needs:
- a fund that **can** be estimated with holdings imported (Parag Parikh can't; try HDFC Mid Cap or Nippon Large Cap);
- FundScope (latest build) open and connected past 3:30 PM on a trading day;
- that evening's AMFI NAV.

The first comparison appears the same night. "Not enough history" shows until 30 trading days are reconciled.

## Known limitations
- Saving needs FundScope running at the close. There's no background helper or login item yet (Phase 8).
- NSE's official close is a 30-minute VWAP; the estimate uses Kite's last price. This is a known error source (docs/10-nav-engine.md).
