# Phase 1 report — 2026-10-29

## Implemented
- **Xcode project** (`FundScope.xcodeproj`): macOS 15 app target with folder-synced groups, local Swift package `FundScopeCore`, UI test target and a shared scheme. Ad-hoc signed (decision D5), App Sandbox (outgoing network, read-only user files), hardened runtime, Swift 6 with main-actor default isolation in the app target.
- **FundScopeCore** (no SwiftUI):
  - Domain value types (`FundInfo`, `SecurityInfo`, `Disclosure`, `Quote`, `Transaction`, `Reconciliation`, …).
  - Engine: `NAVEstimator` (model v1 with coverage rules and not-estimable states), `XIRR`, `PortfolioMath` (average cost, cash-flow-aware value history), `LookThrough` (exposure, overlap, HHI), `DisclosureDiff`, `AccuracyStats`, `Analytics` (screen-ready summaries).
  - `MarketCalendar` (IST sessions, weekends, holiday list), `FinanceFormat` (Indian grouping, ₹, L/Cr, NAV/units/percent/bps).
  - `DemoData`: deterministic dataset with fictional AMCs, funds and companies, so demo numbers can't be mistaken for real ones.
- **Design system**: tokens (spacing, radius, semantic colours with light/dark variants, text styles), `ValueText`, `MissingValue`, `MetricTile`/`MetricStrip`, `BarList`, `CoverageMeter`, `PageHeader`/`Page`/`PageSection`/`TableFrame`, `Pill`, `DemoBadge`, `SourceTag`, `StatusDot`, `MarketStatusBadge`, `EmptyState`/`ErrorState`/`LoadingState`/`InlineNotice`, `RangePicker`, `FundPicker`, `FundMultiPicker`, `ChartTooltip`, `ImportDropZone`, inspector rows.
- **Shell**: `NavigationSplitView` with grouped sidebar and portfolio switcher (Me / Spouse / Family), navigation stack into fund detail, inspector (⌥⌘I), ⌘1–⌘9 and ⌘R, Settings scene with an appearance setting (System/Light/Dark).
- **Screens with demo data**: Onboarding (welcome + setup), Overview, My Portfolio (holdings, transactions, accounts, imports), Live NAV, Fund detail (Today, NAV history, Holdings), Fund Explorer, Compare Funds, Holdings Analysis, Portfolio Changes, NAV Accuracy, Alerts, Data Sources, Settings.

## Tests run
- `swift test --package-path Packages/FundScopeCore` → **30 passed** (estimator hand-computed cases, XIRR against the spreadsheet `XIRR()` example, average cost, look-through, overlap, disclosure diff, accuracy stats, calendar, formatting, demo determinism, analytics consistency, rounding edges).
- `xcodebuild -scheme FundScope test` → **4 UI tests passed**: every section in light and dark mode (each must show the Demo badge), first-launch onboarding, open fund detail from Live NAV.

## Build
`xcodebuild -project FundScope.xcodeproj -scheme FundScope -configuration Debug build` → succeeded, 0 errors, 0 warnings.

## Verified in the running app
Screenshots from the UI tests were reviewed for Overview, Live NAV, Fund detail, Compare, Holdings Analysis, Portfolio Changes and Onboarding. Fixes made after review:
- Metric values were truncated → whole rupees in tiles, with scale-to-fit.
- Light-mode test was rendering dark → added a real appearance setting.
- Negative "unmapped" exposure from weight rounding → fixed in `LookThrough`, with a test.
- "−0.00%" → percent sign now follows the rounded value.
- Coverage was tagged "Official" → now "Holdings · date".
- Portfolio Changes showed a negative change under "Increased" → added a quantity-change column.

## Known limitations
- Import, Kite Connect, AMFI, menu bar, notifications and persistence are not built. Their controls are disabled and labelled with the phase that adds them.
- Demo data is generated in memory (no `Demo.store` yet); refreshing (⌘R) regenerates it for the current time.
- Live NAV doesn't tick on its own yet; streaming arrives in Phase 4.
- Alert rule toggles aren't saved.
- No app icon yet (Phase 8).
- Visual review was done from screenshots at one window size (1280×820). The minimum window size wasn't checked.
- The project isn't a git repository yet.

## Next steps (Phase 2)
1. Get real anonymised Coin holdings and Console tradebook exports into `Fixtures/`.
2. SwiftData schema V1 and the real store, loading into `Dataset`.
3. CSV reader, header detection, column mapping, validation, dedupe, preview, atomic commit, import history.
4. XLSX (add CoreXLSX after checking it's still maintained).
5. Turn on the onboarding import path and the My Portfolio import tab.
