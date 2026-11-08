# 05 — App flow

## Window structure
`NavigationSplitView` with three regions:
- **Sidebar** (always visible, collapsible): navigation and portfolio switcher.
- **Content**: the selected screen.
- **Inspector** (`.inspector`, toggle ⌥⌘I): details of the selected fund, stock, transaction or data source. Hidden when nothing is selected.

Window remembers size, sidebar width, inspector state and last section (`@SceneStorage` / `@AppStorage`). Minimum size 1000 × 640.

## Sidebar

```
[ Portfolio: Me ▾ ]          ← switcher: Me · Spouse · Child · Family (combined)

PORTFOLIO
  Overview                   ⌘1
  My Portfolio               ⌘2
  Live NAV                   ⌘3

RESEARCH
  Fund Explorer              ⌘4
  Compare Funds              ⌘5
  Holdings Analysis          ⌘6
  Portfolio Changes          ⌘7

MONITORING
  NAV Accuracy               ⌘8
  Alerts                     ⌘9

──────────
  Data Sources
  Settings                   ⌘,   (standard Settings window)
```

Settings uses the standard macOS `Settings` scene (tabs: General, Zerodha, Data, Notifications, Advanced). Data Sources stays in the sidebar because it is checked often.

## First launch

```
Launch
  │
  ├─ store has data? ── yes ──► Overview
  │
  no
  ▼
Welcome
  "Your mutual funds, beyond the NAV."
  "Track your investments, understand the companies behind your funds,
   and monitor estimated performance throughout the market day."
  [Get started]          (secondary link: "Explore with demo data")
  │
  ▼
Portfolio setup
  ┌────────────────────────────────┐  ┌────────────────────────────────┐
  │ Import Zerodha Coin portfolio  │  │ Connect Zerodha                │
  │ RECOMMENDED                    │  │ Sync via the official Kite     │
  │ Import holdings and transaction│  │ Connect API.                   │
  │ history from Coin or Console   │  │ Needs your own Kite Connect    │
  │ exports.                       │  │ app (API key + secret).        │
  │ [Import portfolio]             │  │ [Connect Zerodha]              │
  └────────────────────────────────┘  └────────────────────────────────┘
  │                                       │
  ▼                                       ▼
Name portfolio + account            Credentials help sheet → login in browser
("Me", account label)                → success: fetch MF holdings → preview
  │                                  → fail / no credentials: explain,
  ▼                                    [Import a file instead] (never a dead end)
File picker / drop zone
  │
  ▼
Import preview (see 09-import)
  file name · detected type · funds · transactions · total units
  invalid · duplicates · missing identifiers
  [Review records]  [Map columns]  [Import]
  │
  ▼
Import success
  funds · accounts · transactions imported · warnings
  Next: "Fetch official NAVs" (runs automatically) 
  [View my portfolio]
  │
  ▼
My Portfolio (real data)
```

Onboarding is a sheet on top of the main window, not a separate window, so the app shape is visible behind it. It can be reopened from Settings → General → "Run setup again".

### Demo mode
- "Explore with demo data" opens the Demo store. A `DemoBadge` appears in every page header and in the menu bar.
- Leaving demo mode: Settings → General → "Exit demo", or the onboarding "Import portfolio" action.
- Demo and real stores are separate files; nothing can mix.

## Core journeys

### J1 — Morning check (market open)
Menu bar shows `▲ 0.42%` → click → popover: estimated value, day P&L, market status, best/worst fund → "Open FundScope" → Overview.

### J2 — Why is my fund down today?
Live NAV → select fund → fund detail: intraday estimated NAV chart vs official baseline → top negative contributors → click a stock → inspector shows the stock price, which of my funds hold it, and my combined exposure.

### J3 — Monthly update
AMC publishes disclosure → user downloads XLSX → drag onto Fund Explorer or Data Sources → mapping (auto or manual) → snapshot saved → Portfolio Changes shows new/exited/increased/decreased holdings.

### J4 — New SIP instalment
Export from Console → drag onto My Portfolio → preview shows only the new transactions (old ones are duplicates) → Import.

### J5 — Kite token expired
Any Kite call → 403 → status "Requires authentication" in Data Sources, toolbar and menu bar → Reconnect → browser login → resumes. Cached values stay visible with timestamps meanwhile.

### J6 — Accuracy review
NAV Accuracy → pick fund or all → error chart over time, MAPE, median, worst day → click a day → inspector: estimate, official, coverage, holdings snapshot date, model version.

### J7 — Family view
Sidebar switcher → "Family" → every screen shows combined numbers; tables gain a "Portfolio" column; each account's records stay separate.

## Keyboard shortcuts
| Action | Shortcut |
|--------|----------|
| Sections | ⌘1–⌘9 |
| Add funds | ⇧⌘N |
| Sync now | ⌘R |
| Find / search | ⌘F |
| Toggle inspector | ⌥⌘I |
| Toggle sidebar | ⌃⌘S |
| Settings | ⌘, |
| Switch portfolio | ⌃⌘1–4 |
| Open selected fund | Return / double-click |

## Menu bar extra
- Title: estimated daily % (and optionally ₹ P&L) with an arrow, or "FundScope" when no data. "Prev" suffix when showing the previous session.
- Popover: estimated value, day P&L, market status, last update, top and worst fund, "Open FundScope", "Sync now", "Quit".
- Toggle in Settings → General. The app can stay in the menu bar after the main window closes.

## Notifications (Phase 8)
- Daily move beyond a threshold (portfolio or fund).
- Official NAV published; estimate error larger than X%.
- Data stale or Kite needs reconnect (at most once per day).
- New disclosure imported with large changes.
Each notification opens the relevant screen.
