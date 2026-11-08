# 08 — Data sources

> Everything here must be checked against the live documentation before implementation (Phase 3/4). Facts marked **[verify]** are from memory and may be out of date. Never invent endpoints.

## A — Zerodha Kite Connect

> **As built (2026-10-29), checked against kite.trade/docs/connect/v3:** login at `kite.zerodha.com/connect/login?v=3&api_key=…` (a random `state` goes through `redirect_params`) → `POST /session/token` with `checksum = SHA-256(api_key + request_token + api_secret)` → `Authorization: token api_key:access_token` with `X-Kite-Version: 3`. The token expires at 6 AM the next day. Quotes use `GET /quote?i=NSE:SYMBOL` (≤500 per request, 1 request/second), with `last_price`, `ohlc.close` (the previous trading day) and `timestamp`. A 403 `TokenException` means reconnect; 429 means rate-limited. Kite's instrument list has **no ISINs**, so ISIN → symbol comes from NSE's public `EQUITY_L.csv` (verified, ~2,600 stocks). Pricing (zerodha.com/products/api): **Connect ₹500/month**, with streaming and historical data; **Personal is free** but has no live quotes, WebSockets or historical data (confirmed on the developers.kite.trade app form, 2026-10-29). The form lists Connect as "500 credits for 30 days". Redirect `http://127.0.0.1:7313/kite` is accepted by the developer console. **Verified end to end with a real Connect app on 2026-10-29:** login, token exchange and `/quote` prices for the stocks in an imported disclosure. Not built: WebSocket streaming (REST polling once a minute instead), MF holdings sync (not needed with the watchlist design), historical candles.

Docs: https://kite.trade/docs/connect/v3/

### What it gives us
| Need | Endpoint (per v3 docs) | Notes |
|------|-----------------------|-------|
| MF holdings | `GET /mf/holdings` | Current Coin holdings: fund, ISIN, quantity, average price, last price. **[verify]** fields |
| MF orders | `GET /mf/orders` | Recent orders only; **not** a full transaction history **[verify]** time window |
| MF SIPs | `GET /mf/sips` | Optional, for display |
| MF instruments | `GET /mf/instruments` | CSV of MF instruments |
| Equity instruments | `GET /instruments` | Daily CSV dump; map ISIN → instrument token **[verify]** whether ISIN is present; otherwise map by NSE symbol |
| Quotes | `GET /quote`, `/quote/ltp`, `/quote/ohlc` | Batch up to N instruments per call **[verify]** limit and rate limit |
| Streaming | WebSocket `wss://ws.kite.trade` | Binary tick packets; modes ltp/quote/full; subscription limit per connection **[verify]** |
| Historical | `GET /instruments/historical/{token}/{interval}` | Candles; may need a paid add-on **[verify]** |

### Pricing and plans **[verify on kite.trade before Phase 4]**
- Kite Connect is a paid developer app subscription per month. Zerodha has also offered a lower or free "personal" tier **without** market data. The tier decides whether quotes, WebSocket and historical data are available.
- The Settings screen must show the detected entitlement (try a quote call; on permission error, show "Market data not included in your Kite plan").

### Authentication (personal local app)
1. User creates their own Kite Connect app on developers.kite.trade and gets `api_key` and `api_secret`.
2. Redirect URL is set to a local handler. Options: a custom URL scheme `fundscope://kite-callback` (if Kite accepts non-http redirects **[verify]**) or `http://127.0.0.1:<port>/kite-callback` with a one-shot local listener.
3. App opens `https://kite.zerodha.com/connect/login?v=3&api_key=…` in the browser (or `ASWebAuthenticationSession`). The user logs in on Zerodha's own page. **FundScope never sees the password.**
4. Redirect returns `request_token`. App sends `POST /session/token` with `api_key`, `request_token`, and `checksum = SHA256(api_key + request_token + api_secret)`.
5. Store `access_token` in Keychain. It expires daily (early morning IST **[verify]**). On 403 / `TokenException`, mark status "Requires authentication" and offer Reconnect.

Is it safe to do the secret exchange inside the app? **Yes, for this case**: it is the user's own secret for their own app, entered by them, kept in their own Keychain, and never shipped inside the binary.

Family distribution (decision D5): the same build is installed on family Macs, and **each person creates their own Kite Connect app and enters their own key and secret**. The binary never contains any secret. Sharing one Kite app or token between people is not supported. If the app were ever shared beyond family, the secret exchange would need a server and the design must be revisited. **[verify]** whether Zerodha's terms allow one Kite Connect app to be used only by its owner, and whether each family member needs a separate subscription.

### Allowed use
Read-only. No order placement endpoints are ever called. The Kite module must not even contain order code.

### Nifty 50 (verified 2026-10-30)
- Constituents: NSE `https://nsearchives.nseindia.com/content/indices/ind_nifty50list.csv` (header `Company Name,Industry,Symbol,Series,ISIN Code`, 50 rows). Cached and refreshed weekly with the other NSE lists.
- Index level: Kite `/quote` with instrument `NSE:NIFTY 50`. `last_price` is the index level and `ohlc.close` the previous close. Tested against the live service during market hours.
- ETF symbols: NSE `https://nsearchives.nseindia.com/content/equities/eq_etfseclist.csv` (`Symbol`, `ISINNumber`), used to price ETF holdings such as a gold ETF. NSE publishes no equivalent list for REITs or InvITs.

## B — AMFI (official NAV)

Site: https://www.amfiindia.com/

| Need | Source **[verify current URLs]** |
|------|----------------------------------|
| Latest NAV for all schemes + scheme directory | **Verified 2026-10-29:** `https://portal.amfiindia.com/spages/NAVAll.txt` (www.amfiindia.com redirects there), ~1.5 MB, ~14,400 schemes. Header: `Scheme Code;ISIN Div Payout/ ISIN Growth;ISIN Div Reinvestment;Scheme Name;Plan;Option;Net Asset Value;Date`, grouped under category lines like `Open Ended Schemes(Equity Scheme - Small Cap Fund)` and AMC name lines. The parser reads column positions from the header, so the older 6-column layout works too |
| Historical NAV | **Used, verified 2026-10-29:** the API behind AMFI's public NAV History page, `https://www.amfiindia.com/api/nav-history?query_type=historical_period&from_date=YYYY-MM-DD&to_date=YYYY-MM-DD&sd_id=<scheme code>`. JSON, one scheme per request; the range must be under 5 years (HTTP 400 otherwise); an unknown scheme returns `{"message":"No records to display"}`. About 140 KB and ~19 s for 3 years. FundScope asks for 5 years in ≤3-year chunks, 3 requests at a time; all 14 watched funds took ~2.3 min. **[verify periodically]** This is an undocumented endpoint used by AMFI's own site, so it may change; failures show a warning and keep the stored history. (The older `DownloadNAVHistoryReport_Po.aspx` covers every scheme, ~21 MB per month, so it isn't used.) |

Parsing rules:
- Header lines (category, AMC name) have no semicolons; use them to set the current AMC/category.
- NAV may be `N.A.` → treat as missing, not zero.
- Date format `dd-MMM-yyyy`.
- Keep the scheme code as the key. ISIN columns may be `-` or blank.

Etiquette: one fetch per job run, with backoff on failure. No parallel hammering.

## C — AMC portfolio disclosures

> **As built (2026-10-29):** manual import of the monthly portfolio file (⇧⌘I). `DisclosureParser` finds the header row (ISIN + "% to Net Assets/NAV/AUM"), reads sections (equity, arbitrage → hedged, REITs, foreign, debt and money market, fund units, TREPS, net receivables), handles weights given as fractions or percents, and stops at GRAND TOTAL (the futures listed after it are the arbitrage hedges). Verified on PPFAS Flexi Cap for Aug and Sep 2026, where every section matches the file's own sub-totals. **[verify]** each new fund house's layout as its files are imported. Download access checked 2026-10-29: PPFAS has direct links; HDFC returns 403 to scripts; ICICI, Invesco and Nippon build links in JavaScript. So import stays manual, with no scraping.

- SEBI requires monthly portfolio disclosure from every AMC (published on the AMC's website, usually as XLSX, often one file with one sheet per scheme).
- Formats differ by AMC and change over time. Approach:
  - Generic parser: find the header row by looking for column names like "ISIN", "Name of the Instrument", "% to NAV"/"% to Net Assets", "Quantity", "Market value".
  - Per-AMC `DisclosureMapping` (sheet name → scheme, header row, column indexes, section markers such as "Equity & Equity related", "Debt Instruments", "TREPS", "Net Receivables").
  - Manual mapping UI when detection is unsure (same UI as the Coin import mapper).
- Asset type comes from the section the row is in, plus the ISIN prefix (`INE` = Indian company; `INF` = MF unit; `IN0`/`IN1`… = government securities, etc.) **[verify ISIN prefix rules]**.
- Import is manual in v1: the user downloads the file from the AMC site and drops it in. Automatic download only if an AMC offers a stable, permitted URL.
- First mappings (decision D3): **PPFAS, HDFC, ICICI Prudential**, in that order unless the first Coin import shows a different largest holding. Others use the generic parser + manual mapping.

## D — Historical market prices
- Primary: Kite historical candles (if entitled).
- Fallback: daily closes collected by the app itself from live quotes, from the day it starts running.
- NSE/BSE bhavcopy: only if downloading is permitted by their terms; check in Phase 4. Not planned by default.

## E — Benchmarks
- Source (decision D4): **index quotes and historical candles from Kite** (e.g. NIFTY 50, NIFTY 500, NIFTY Midcap 150) via their index instrument tokens **[verify]** that the plan includes index quotes and index history.
- These are price indices. TRI (total return) is usually not available; never label a price index as TRI, and note in comparisons that fund NAVs include dividends while the index does not.
- If a benchmark is unavailable, the comparison UI shows "Benchmark unavailable" instead of hiding the gap.

## F — Data Sources health screen
For each provider: name, status, last successful update, latest data date, record count, warnings, Retry.

| Status | Meaning |
|--------|---------|
| Connected | Last call succeeded and data is current |
| Updating | A job is running |
| Stale | Data older than expected (e.g. NAV for D-2 while D-1 is due) |
| Requires authentication | Kite token missing/expired |
| Unavailable | Last call failed (network, 5xx, plan lacks access) |
| Import required | Manual source with no file yet (AMC disclosures, Coin import) |

## What each provider receives
| Provider | Data sent from the Mac |
|----------|------------------------|
| Zerodha Kite | API key, access token, checksum, list of instrument tokens being watched. Kite already knows your holdings. |
| AMFI | A plain GET for the full public NAV file. Identical for everyone, so it doesn't reveal your funds. |
| AMC websites | Nothing (files are downloaded by you in the browser). |
| Anyone else | Nothing. |
