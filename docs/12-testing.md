# 12 — Testing

## Rules
- Unit tests never call live APIs. Network adapters are tested with recorded responses saved in `Fixtures/`.
- Fixtures are deterministic and anonymised. No real client IDs, names or personal amounts.
- Clock and calendar are injected (`now: Date`, `calendar: MarketCalendar`) so tests do not depend on today's date.
- A feature is not done until its tests pass and it has been checked in the running app.

## Layers
| Layer | Tool | Runs |
|-------|------|------|
| Engine + import + parsers | Swift Testing in `FundScopeCoreTests` | `swift test --package-path Packages/FundScopeCore` (seconds) |
| SwiftData models, migrations, import commit | Swift Testing with an in-memory `ModelContainer` | same |
| Provider adapters | Swift Testing with fixture JSON/CSV/binary tick packets | same |
| UI smoke | XCUITest: launch, onboarding with demo data, open each sidebar section | `xcodebuild test` |
| Manual | Checklist below, per phase | by hand |

## Required test areas
| Area | Example cases |
|------|--------------|
| CSV parsing | quoted fields, commas in names, BOM, CRLF, empty lines, ₹ and Indian grouping |
| XLSX parsing | multiple sheets, header not on row 1, merged title rows, numeric dates |
| Scheme matching | ISIN match; growth vs IDCW ISIN; name-only needs confirmation |
| ISIN mapping | equity ISIN → Security; unknown ISIN kept as unmapped |
| Duplicate detection | same file twice → 0 new; overlapping files; two identical SIPs same day |
| Portfolio valuation | units × NAV; missing NAV → nil, not 0 |
| XIRR | spreadsheet-verified cases; non-convergence → nil |
| NAV estimation | hand-computed 3-stock fund; cash residual; unpriced weight; not-estimable threshold |
| Missing prices | stale quote excluded and counted |
| Stale holdings | disclosure older than 45 days → warning |
| Corporate actions | adjusted previous close; split-like quantity change flagged |
| Holidays | baseline across a holiday |
| Reconciliation | error maths; original estimate unchanged after reconcile |
| Multiple accounts | combined family totals = sum of accounts; records stay separate |
| History preservation | re-importing a disclosure does not change the old snapshot |
| AMFI parser | header lines, `N.A.` NAV, missing ISIN |
| Kite | checksum calc; token-expired error → auth-required state; binary tick decoding |
| Migrations | open V(n-1) store fixture with V(n) |

## Live checks (opt-in)
`FUNDSCOPE_LIVE=1 swift test --package-path Packages/FundScopeCore --filter LiveAMFI` downloads AMFI's daily file and 5 years of history for the watched funds. There's no UI and nothing is stored. Never part of the normal test run.

## UI tests and privacy
UI tests take control of the mouse and keyboard. Run them only when nobody is using the Mac. The scheme sets `systemAttachmentLifetime = keepNever`, so Xcode doesn't keep automatic screenshots or screen recordings (a failed run once recorded the whole screen). Tests attach only screenshots of FundScope's own window.

## Build verification (every phase)
1. `xcodebuild … build` — 0 errors, 0 warnings (Swift 6 strict concurrency).
2. `swift test` — all pass.
3. `xcodebuild … test` — UI smoke passes.
4. Run the app: check every changed screen in light and dark mode, at minimum window size and large size.
5. Write the phase report (template in [ROADMAP](../ROADMAP.md)).

## Manual checklist per release
- [ ] Fresh launch → onboarding appears
- [ ] Import real Coin export → numbers match Coin/Console
- [ ] Quit and reopen → data intact
- [ ] Re-import same file → 0 new records
- [ ] Turn off Wi-Fi → cached values with timestamps, no fake numbers
- [ ] Kite: connect, expire (disconnect), reconnect
- [ ] Market hours: estimates move; after close: "Prev session" label
- [ ] Next morning: reconciliation row exists
- [ ] VoiceOver reads metric labels and values
- [ ] Keyboard-only navigation works
