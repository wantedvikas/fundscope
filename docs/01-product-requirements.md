# 01 — Product requirements

> **Direction change (2026-10-29, decision D7):** FundScope is a **watchlist of funds you name**. It doesn't import or store anything about your money: no units, amounts, P&L, XIRR or accounts. Requirements F1–F3 and F10 below are dropped; "portfolio" figures are equal-weight averages across watched funds.

## Purpose
A personal macOS app for tracking my Indian mutual fund investments held in Zerodha Coin. It shows what I own, what it is worth officially, what it is probably worth right now based on the stocks inside each fund, and how good those estimates have been.

## Users
- **Primary:** me, one person on one Mac.
- **Family:** several local portfolios (Me, Spouse, Child) that are tracked separately and can also be viewed combined. There is no login; everything is local.

## Out of scope
- SaaS, servers, sync between devices, public accounts, subscriptions, payments.
- Placing orders, SIP changes, or any trading.
- Collecting the Zerodha password.
- Scraping websites without permission.
- Investment advice or recommendations.
- iOS, iPadOS, Windows and web versions.

## Functional requirements

| ID | Requirement | Phase | Priority |
|----|-------------|-------|----------|
| F1 | Import Zerodha Coin/Console holdings and transaction exports (CSV, XLSX) | 2 | Must |
| F2 | Optional Kite Connect connection for MF holdings, orders, quotes, streaming, historical prices | 4 | Should |
| F3 | Automatic portfolio sync when Kite is connected and the plan allows it | 4 | Could |
| F4 | Official NAV from AMFI, daily and historical | 3 | Must |
| F5 | Estimated intraday NAV from disclosed holdings and live prices | 5 | Must |
| F6 | Live prices of underlying stocks | 4 | Must |
| F7 | Fund holdings with each stock's contribution to NAV change | 5 | Must |
| F8 | Estimated vs official NAV comparison | 6 | Must |
| F9 | Historical estimation accuracy | 6 | Must |
| F10 | Multiple portfolios and accounts, with a combined family view | 2, 7 | Must |
| F11 | Combined stock and sector exposure (look-through) | 7 | Must |
| F12 | Fund overlap analysis | 7 | Should |
| F13 | Month-to-month AMC disclosure change detection | 7 | Should |
| F14 | Fund vs fund and fund vs benchmark comparison | 7 | Should |
| F15 | Menu bar tracker | 8 | Should |
| F16 | Native notifications from alert rules | 8 | Should |
| F17 | Local storage, works offline with cached data | 1–2 | Must |
| F18 | Onboarding for first launch | 1–2 | Must |
| F19 | Data source health screen | 3 | Must |
| F20 | Clearly labelled demo mode, never mixed with real data | 1 | Must |

## Non-functional requirements
- **Native:** SwiftUI and AppKit only. No Electron or web views for the main UI.
- **Look and feel:** comparable in craft to Linear, Raycast or Things, without copying them. See [04](04-design-system.md).
- **Correctness:** financial values use `Decimal`. Unknown values are shown as unknown, never as 0.
- **Honesty:** estimated values always look different from official ones. Stale data always shows its timestamp. A failed provider never shows made-up values.
- **Privacy:** data stays on the Mac. No analytics. Secrets live in Keychain.
- **Performance:** app launch under 1 s with cached data; 500-row tables scroll smoothly; live updates no more than about 1 UI refresh per second per screen.
- **Reliability:** an import is all-or-nothing. Historical disclosures and saved predictions never change once written.

## Definition of done
I can:
1. Launch FundScope on my Mac.
2. Complete onboarding.
3. Import my Zerodha Coin portfolio.
4. See my actual mutual fund holdings.
5. See units and invested amounts.
6. See official NAV and portfolio value.
7. Open a fund and see the companies it holds.
8. Connect a supported live market data provider.
9. See estimated live NAV during market hours.
10. See which holdings drive NAV changes.
11. Track estimated portfolio value.
12. Compare estimated NAV with official NAV.
13. Review historical prediction accuracy.
14. See consolidated company and sector exposure.
15. Quit and reopen without losing data.

Every one of these must work with real data, not only demo data.

## Decisions
Decided 2026-10-29.

| # | Question | Decision | Consequence |
|---|----------|----------|-------------|
| D1 | Kite Connect access? | **Will get a paid Kite Connect plan** (with market data) | Phase 4 is built and tested against the real API. Until the subscription is active, development uses the mock market provider. Confirm current price and entitlements on kite.trade before subscribing |
| D2 | Storage | **SwiftData**, intraday ticks in memory with 1/min snapshots | Switch to GRDB only if Phase 4/5 measurements fail the limits in [02](02-tech-stack.md) |
| D3 | First AMC disclosure parsers | **PPFAS, HDFC, ICICI Prudential** (tentative; owner not sure of the full list) | Confirm against the AMCs found in the first real Coin import. PPFAS Flexi Cap holds a large foreign-equity share, so it may show as partly or fully "Not estimable" under the coverage rules in [10](10-nav-engine.md) |
| D4 | Benchmarks | **Index quotes via Kite** (e.g. NIFTY 50) | Labelled as a price index, never as TRI. Hidden with "Benchmark unavailable" if the plan doesn't include index data |
| D5 | Distribution | **My Mac and family members' Macs, with no paid Apple Developer Program** | Builds are signed locally ("Sign to Run Locally"), not notarised. Each family Mac approves the app once in System Settings → Privacy & Security → **Open Anyway**, and again after each update. Each person enters their **own** Kite credentials; nothing is embedded in the app. No auto-update. See [11 §Distribution](11-security-privacy.md#distribution-to-family-macs-decision-d5) |
| D8 | Live price source | **Kite Connect only** (confirmed 2026-10-29) | Requires a once-a-day login on Zerodha's page (Kite issues no access token any other way; it expires at 6 AM). No unofficial feeds or scraping |
| D7 | Personal amounts | **Never stored.** Funds are added by name (search, pasted list, or the name column of a holdings file). Zerodha import removed; combined exposure uses equal weights | Simpler and private. Live estimates still need Kite Connect for stock prices only |
| D6 | Minimum macOS | **macOS 15** | Toolchain: Xcode 27.1, Swift 6.4. Family Macs must run macOS 15 or later; check this before Phase 8 |
