# 02 — Tech stack

## Toolchain (checked 2026-10-29)
- Xcode 27.1 (27A9275)
- Swift 6.4, Swift 6 language mode with strict concurrency
- Deployment target: macOS 15.0

## Choices

| Area | Choice | Why |
|------|--------|-----|
| Language | Swift 6 | Native; strict concurrency catches data races in streaming code |
| UI | SwiftUI | Required; AppKit only where SwiftUI cannot do the job (e.g. `NSTableView` if `Table` is too slow) |
| State | Observation (`@Observable`) | Modern replacement for `ObservableObject` |
| Charts | Swift Charts | Native, supports hover selection and dark mode |
| Storage | SwiftData (default) | Built in, supports migrations, works with SwiftUI. See "Storage decision" |
| Networking | `URLSession` (async/await) | No dependency needed |
| Streaming | `URLSessionWebSocketTask` | Built-in WebSocket client, enough for Kite ticks |
| Secrets | Keychain Services (`SecItem*`) | Required for API secret and access token |
| Notifications | UserNotifications | Native local notifications |
| Menu bar | `MenuBarExtra` (`.window` style) | Native popover-style menu bar item |
| Background refresh | `NSBackgroundActivityScheduler` while running | Only while the app or menu bar item is running; no launch agent |
| File import | `.fileImporter`, `.dropDestination` | Native |
| CSV | Own parser (RFC 4180, ~100 lines) | Simple format; a dependency is not justified |
| XLSX | **ZIPFoundation** + own ~100-line reader (`XMLParser`) | CoreXLSX was last updated March 2024 and predates Swift 6; ZIPFoundation is maintained. We read shared strings, inline strings and values only: no formulas, styles or macros |
| Hashing | CryptoKit `SHA256` | Kite checksum and import file fingerprints |
| Tests | Swift Testing (`@Test`), XCTest only for UI tests | Modern, parallel by default |
| Logging | `os.Logger` with privacy annotations | Native; values marked `.private` by default |

## Dependencies
Only add a dependency when writing the code ourselves would be large and risky.

| Package | Purpose | Status |
|---------|---------|--------|
| ZIPFoundation 0.9.20 (exact) | Unzip `.xlsx` (Coin exports, AMC disclosures) | Added in Phase 2. Only third-party dependency |

No analytics, crash reporting, UI kits, chart libraries or networking libraries.

## Storage decision
SwiftData is the default. Switch to SQLite through GRDB if any of these happen in Phase 4/5 testing:
- Writing intraday quotes (about 50–150 stocks per fund × ticks) blocks the UI or takes more than 50 ms per batch.
- The aggregation queries for look-through exposure need joins or `GROUP BY` that SwiftData cannot express efficiently.

Lower-risk middle path: keep SwiftData for portfolio data, and keep intraday ticks **only in memory**, saving one snapshot per minute per fund. Try this first.

## Project layout
```
FundScope/
├── FundScope.xcodeproj
├── FundScope/                  # App target: SwiftUI views, app entry, menu bar
│   ├── App/
│   ├── DesignSystem/           # Tokens + shared components
│   ├── Features/               # One folder per sidebar section
│   └── Resources/
├── Packages/FundScopeCore/     # Local Swift package, no SwiftUI import
│   ├── Sources/FundScopeCore/
│   │   ├── Models/             # SwiftData models
│   │   ├── Import/             # CSV/XLSX parsing, mapping, validation
│   │   ├── Providers/          # Protocols + Zerodha, AMFI, AMC, Mock adapters
│   │   ├── Engine/             # NAV estimate, reconciliation, XIRR, look-through
│   │   └── Services/           # Sync, Keychain, scheduling
│   └── Tests/FundScopeCoreTests/
├── Fixtures/                   # Anonymised sample files for tests
├── docs/
├── AGENTS.md
└── ROADMAP.md
```

Keeping the core in a package means the calculation and import code can be tested quickly with `swift test`, without launching the app.

## Signing and distribution
- No paid Apple Developer Program (decision D5). All builds use ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`), with hardened runtime and App Sandbox on.
- Family Macs: Release build, zipped, then approved once per build via Privacy & Security → Open Anyway. There's no notarisation. Steps are in [11](11-security-privacy.md#distribution-to-family-macs-decision-d5).

## Build commands
```bash
xcodebuild -project FundScope.xcodeproj -scheme FundScope -configuration Debug build
```
```bash
swift test --package-path Packages/FundScopeCore
```
```bash
xcodebuild -project FundScope.xcodeproj -scheme FundScope test
```
