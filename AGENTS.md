# AGENTS.md — FundScope engineering rules

Read this before changing anything. These rules apply to every contributor, human or AI. Detailed specs are in `docs/`; the order of work is in `ROADMAP.md`.

## What this is
A native macOS (15+) SwiftUI app for tracking personal Indian mutual funds held in Zerodha Coin. Local-only, read-only, single user with family portfolios.

## Hard rules
1. Native only: SwiftUI (+ AppKit where needed). No Electron, no web views for app UI.
2. Never hardcode, log or commit API secrets or tokens. Keychain only.
3. Never ask for or handle the Zerodha password. Never place orders.
4. Never fabricate portfolio or market data. Unknown → `nil` → shown as "—" with a reason.
5. Never silently drop data: unmapped holdings, unpriced stocks and failed rows are counted and shown.
6. Demo data lives only in the demo store and always shows a Demo badge.
7. Do not invent API endpoints. Check the official docs; mark anything unverified.
8. Never claim an integration works unless it has been tested against the real service.
9. Keep the app compiling after every change. Run tests after every meaningful change.
10. Do not mark a feature done without verifying it in the running app.

## Swift 6 conventions
- Swift 6 language mode, strict concurrency, zero warnings.
- `@Observable` for state; no `ObservableObject`/`@Published` in new code.
- `@MainActor` on UI models. Background work in `actor`s or `@ModelActor`.
- `async`/`await` everywhere; no completion handlers, no Combine for new code.
- Value types (`struct`, `enum`) by default; `final class` only for SwiftData models and shared mutable services.
- Naming: types `UpperCamelCase`, members `lowerCamelCase`, one main type per file, file named after it.
- No force unwraps outside tests, except for compile-time constants (e.g. a hard-coded valid URL literal).
- Don't add abstractions, protocols or options until a second real use exists. The five provider protocols are the exception (they are part of the design).

## SwiftUI architecture
- Views are small and declarative. No networking, parsing or maths in views.
- Feature folder per sidebar section: `Features/<Section>/<Section>View.swift`, `<Section>Model.swift`.
- Views read stored data with `@Query`; actions go through Core services.
- Use modern APIs: `NavigationSplitView`, `.inspector`, `Table`, `.searchable`, `.fileImporter`, `.dropDestination`, `MenuBarExtra`, `Settings` scene, Swift Charts.
- No deprecated APIs (`NavigationView`, `onChange(of:perform:)` single-param form, etc.).

## Design system rules
- Use only tokens from `DesignSystem/` for spacing (4, 8, 12, 16, 20, 24, 32, 40), radius, colour and text styles. No literal numbers or colours in feature views.
- Use shared components (`MetricTile`, `FinancialTable`, `EmptyState`, …). If one doesn't fit, extend it in `DesignSystem/` — no one-off styling.
- Monospaced digits for every number. Indian number grouping.
- Green/red only for financial direction, always with a +/− sign too.
- Estimated values must look different from official ones (Est./≈ label, dashed line).
- Every screen handles loading, empty, error, offline, missing-data and demo states.
- Check light and dark mode for every UI change.
- Spec: `docs/04-design-system.md`.

## Financial calculation precision
- `Decimal` for money, NAV, units and weights in storage and engine. `Double` only for chart plotting.
- NAV 4 dp, units 3 dp, percent 2 dp for display. Round only at display time.
- Engine code is pure: no SwiftData, network or `Date()` inside; inputs passed in.
- Valuation date is separate from retrieval time. Dates are IST trading dates.
- Saved estimates, disclosures and reconciliations are never edited after they are written.
- Every estimate stores its model version, holdings snapshot date and coverage.
- Spec: `docs/10-nav-engine.md`.

## API security
- Secrets in Keychain (`WhenUnlockedThisDeviceOnly`). Never in `UserDefaults`, SwiftData, logs, fixtures or source.
- HTTPS only; allowed hosts listed in `docs/11-security-privacy.md`.
- Log with `os.Logger`; mark sensitive values `.private`.
- No third-party SDKs without updating `docs/02-tech-stack.md` and giving a reason.

## Data validation
- Validate every imported row and every API response at the boundary. Bad data becomes a visible error or warning, never a crash and never a guessed value.
- Imports: preview first, commit atomically, duplicate-safe (re-import adds nothing).
- Match schemes by ISIN. Name-only matches need user confirmation.

## Error handling
- Use `FundScopeError` with a user-facing message and a recovery action.
- Network failures keep showing cached data with its timestamp.
- Never show a fake or zero value because a call failed.

## Testing
- Swift Testing for Core; XCUITest for smoke tests.
- No live API calls in tests. Deterministic fixtures in `Fixtures/`, anonymised.
- Inject the clock and market calendar.
- New engine or parser logic comes with tests in the same change.
- Spec: `docs/12-testing.md`.

## Build verification
Before saying anything is done:
```bash
xcodebuild -project FundScope.xcodeproj -scheme FundScope -configuration Debug build
swift test --package-path Packages/FundScopeCore
```
Then run the app and check the changed screens (light + dark).

## Documentation
- Update the relevant `docs/` file in the same change as the code it describes.
- End each phase with a phase report in `ROADMAP.md` format.
- Mark unverified external facts with **[verify]** until checked.
- Mark known shortcuts in code: `// shortcut: <limit>, <when to upgrade>`.
