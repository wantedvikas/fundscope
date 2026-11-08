# 06 — Screens

Each screen lists content, layout and the states it must handle. Shared states for **every** screen:

| State | Behaviour |
|-------|-----------|
| Loading | `LoadingState` (skeleton table rows or a small progress indicator in the header). No spinners over content that is already shown |
| Empty | `EmptyState` saying why it is empty and one action, e.g. "No funds tracked yet. Import your Zerodha Coin portfolio to get started." [Import portfolio] |
| Error | `ErrorState` with what failed and Retry/Resolve |
| Offline | Cached values with "Updated 28 Oct, 21:04" and a stale `StatusDot` |
| Missing data | `MissingValue` ("—") with a reason tooltip; never 0 |
| Demo | `DemoBadge` in the header |

---

## Overview (most polished screen)
**Header:** "Overview", portfolio name, market status, last update.

**Metric strip:** Total invested · Official value (date) · Est. live value · Est. day P&L · Absolute return · XIRR.

**Main chart:** portfolio value over time; range 1M/3M/6M/1Y/3Y/5Y/All. Two series: *value* and *net invested* (cumulative cash flows), so the effect of new money is visible. A note under the chart: "Value includes new investments. Returns: see XIRR." Hover tooltip with value, invested, gain.

**Fund table:** Fund · Units · Invested · Official value · Est. value · Est. day P&L · Total return · XIRR. Sort, search, Return opens fund.

**Allocation:** category, market cap, sector, AMC, top 10 underlying companies. Horizontal bar charts (no pies/donuts unless ≤ 4 parts).

**Inspector:** selected fund summary.

## Live NAV
**Table of tracked funds:** Fund · Official NAV (date) · Est. NAV · Est. change % · Coverage · Holdings as of · Updated. Unsupported fund types show "Not estimable" with the reason.

**Fund NAV detail** (push from row):
- Header: fund name, AMC, category, plan, latest official NAV, est. live NAV, est. day return, market status, last update.
- Chart: intraday estimated NAV (dashed), official baseline (solid horizontal), optional benchmark, hover tooltip, date picker for past days.
- Top positive and top negative contributors (two short lists side by side).
- Holdings table: Company · Weight · Prev. valuation price · Latest price · Change % · Est. NAV contribution (bps) · Quote freshness. Sort, filter (sector, priced/unpriced).
- Sector contribution bars.
- `CoverageMeter` + warnings ("Holdings as of 30 Sep; 6.2% weight in cash/debt treated as flat; 1.1% unpriced").

## Nifty 50 (sidebar → Market)
- Header: "Nifty 50", "NSE · updated HH:mm:ss", and the market status badge.
- Metric strip: index level with today's % change, change in points (signed and coloured), and how many stocks are advancing and declining.
- Table of the 50 stocks: company, symbol, industry, price, ₹ change and % change. It's sorted by % change, high to low, and is searchable. Price and both changes are green when up and red when down, always with a +/− sign.
- Updates itself: while the page is open, one Kite `/quote` request for the index and all 50 stocks runs every 2 s in market hours and once a minute otherwise. It stops when you leave the page. If a fetch fails, the last prices stay; a warning appears only when they're more than 10 s old.
- States: Kite not connected (warning, prices "—"); list downloading (loading); fetch failing (warning with the last prices kept). Works in demo mode too, because it's market data, not portfolio data.

## My Portfolio
- Segmented: **Holdings** | **Transactions** | **Accounts** | **Imports**.
- Holdings: per fund, per account; units, avg cost, invested, official value, return, XIRR.
- Transactions: date, fund, type, units, NAV, amount, account, source import. Filter by type/fund/date.
- Accounts: list, add/rename, assign to portfolio.
- Imports: history with counts and an "Undo import" action (confirmation dialog).
- Toolbar: Import (⌘O), Sync (if Kite).
- Drop zone over the whole screen accepts files.

## Fund Explorer
- Search all AMFI schemes (name, AMC, ISIN, scheme code), filter by category/plan.
- Fund page: NAV history chart, latest disclosure holdings, asset mix, sector mix, disclosure history (dates), "Import disclosure" drop zone, "Track" toggle.

## Compare Funds
- Pick 2–5 funds (+ benchmark if available).
- Tabs: Performance (rebased NAV, range picker; trailing returns table) · Holdings overlap (overlap % matrix, common stocks list) · Allocation (sector, market cap side by side).
- Benchmark missing → "Benchmark unavailable — no permitted data source configured."

## Holdings Analysis (look-through)
- Metric strip: # unique companies, top-10 concentration, largest single company %, unmapped %, unsupported %.
- Tabs: Companies · Sectors · Market cap · Overlap · Concentration.
- Companies table: Company · My effective exposure ₹ · % of portfolio · Funds holding it (count + names in inspector).
- "Unmapped" and "Unsupported (debt/cash/foreign/derivatives)" are always shown as their own rows.

## NAV Accuracy
- Fund picker (All / one fund), range.
- Metric strip: Reconciled days · Mean abs % error · Median · Worst · Trend (last 30 vs previous 30).
- Chart: % error per day (bars), zero line, ±0.25% band shown for reference only.
- Table: Date · Fund · Estimated · Official · Error · Error % · Coverage · Holdings as of · Model version.
- Copy at the top while fewer than 30 reconciled days: "Not enough history to judge accuracy yet."

## Portfolio Changes
- Pick fund, pick two disclosure months (default: latest two). Disclosure dates shown large.
- Sections: New · Exited · Increased · Decreased · Sector changes · Concentration change.
- Each change marked **Quantity change (confirmed)** when quantities exist in both files, or **Weight change (may be price movement)** when only weights exist.

## Alerts
- Rules list (toggle, edit, delete) + "New rule" sheet.
- History of fired alerts.
- Shows if notification permission is denied, with a button to open System Settings.

## Data Sources
- One `ConnectionCard` per provider: Zerodha (Kite), AMFI, AMC disclosures, Market data, Benchmarks, Coin import.
- Each: status, last success, latest data date, records, warnings, Retry / Reconnect / Import.
- Sync log (last 50 `SyncRecord`s).

## Settings (Settings scene)
- **General:** launch at login, menu bar toggle, default portfolio, demo mode, run setup again.
- **Zerodha:** status, API key field, API secret field (both to Keychain), redirect URL to copy, last connection, last sync, market data entitlement, Connect / Reconnect / Disconnect / Sync now, link to "How to get Kite Connect access".
- **Data:** AMFI refresh schedule, intraday retention, store location, back up / restore, delete all data (double confirmation).
- **Notifications:** per-rule-type toggles.
- **Advanced:** model version, logs location, reset caches.
