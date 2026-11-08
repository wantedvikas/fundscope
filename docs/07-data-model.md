# 07 — Data model

## Principles
- **Money and NAV:** `Decimal`. Never `Double` for stored values. `Double` is allowed only inside chart plotting.
- **Units:** `Decimal`, kept to 3 decimal places (that is how Indian MF units are allotted).
- **Stable identifiers:** use the natural key where there is one (ISIN, AMFI scheme code, Kite instrument token). Generate a UUID only where none exists.
- **Two kinds of time:** `valuationDate` (the market date a value is for, stored as a date with no time, in IST) is always separate from `retrievedAt` (when we fetched it).
- **Immutable history:** `FundPortfolioSnapshot`, `FundHolding`, `EstimatedNAV` (once frozen) and `NAVReconciliation` are insert-only.
- **Unknown is not zero:** optional fields stay `nil` when a value is not known.

## Entities

### Reference data
| Entity | Key fields | Notes |
|--------|-----------|-------|
| **FundScheme** | `amfiCode` (unique), `isinGrowth`, `isinIDCW`, `name`, `amc`, `category`, `plan` (direct/regular), `option` (growth/IDCW), `isEstimable` | One row per AMFI scheme code. A plan's NAV is not the same as another plan's |
| **Security** | `isin` (unique), `name`, `nseSymbol?`, `kiteInstrumentToken?`, `sector?`, `marketCapBucket?`, `assetType` (equity/debt/cash/derivative/foreignEquity/reit/other) | Shared by all funds |
| **OfficialNAV** | `scheme`, `valuationDate`, `nav`, `source`, `retrievedAt` | Unique on (scheme, valuationDate) |
| **MarketQuote** | `security`, `price`, `previousClose`, `exchangeTimestamp`, `retrievedAt` | Latest quote + per-minute snapshots during the day; older intraday data deleted after 30 days, daily closes kept |

### Fund disclosures
| Entity | Key fields | Notes |
|--------|-----------|-------|
| **FundPortfolioSnapshot** | `scheme`, `disclosureDate`, `sourceFile`, `fileHash`, `importedAt`, `totalNetAssets?` | One per fund per month. Never edited; re-import of the same hash is ignored |
| **FundHolding** | `snapshot`, `security?`, `rawName`, `rawISIN?`, `weightPercent`, `quantity?`, `marketValue?`, `assetType` | `security` is nil when unmapped. Unmapped rows are kept, never dropped |

### Personal portfolio
| Entity | Key fields | Notes |
|--------|-----------|-------|
| **Portfolio** | `id`, `name`, `isCombined` | E.g. "Me", "Spouse". Combined view is computed, not stored as merged records |
| **InvestmentAccount** | `id`, `portfolio`, `broker` (zerodha), `clientIDHint` (last 4 chars only), `displayName` | Several accounts per portfolio allowed |
| **InvestmentHolding** | `account`, `scheme`, `units`, `averageCost?`, `investedAmount?`, `asOf`, `source` (import/kite) | A snapshot of what is held. Not a transaction history |
| **InvestmentTransaction** | `id`, `account`, `scheme`, `date`, `type`, `units`, `amount`, `nav?`, `externalRef?`, `dedupeKey`, `importRecord` | `type`: purchase, sip, redemption, switchIn, switchOut, idcwPayout, idcwReinvest, reversal, other. `dedupeKey` unique per account |

### Estimates and accuracy
| Entity | Key fields | Notes |
|--------|-----------|-------|
| **EstimatedNAV** | `scheme`, `valuationDate`, `computedAt`, `estimatedNAV`, `estimatedReturn`, `baselineNAV`, `baselineDate`, `holdingsSnapshotDate`, `pricedWeight`, `quoteCoverage`, `modelVersion`, `isFinal` | Intraday rows have `isFinal = false`. One frozen `isFinal = true` row per scheme per date |
| **NAVReconciliation** | `scheme`, `valuationDate`, `estimatedNAV`, `officialNAV`, `absError`, `pctError`, `modelVersion`, `holdingsSnapshotDate`, `quoteCoverage`, `reconciledAt` | Unique on (scheme, valuationDate, modelVersion) |

### Operations
| Entity | Key fields | Notes |
|--------|-----------|-------|
| **ImportRecord** | `id`, `fileName`, `fileHash`, `detectedKind`, `account`, `importedAt`, counts (added, skipped duplicates, invalid), `warnings` | Import history; can be undone (deletes rows linked to this record) |
| **SyncRecord** | `provider`, `startedAt`, `finishedAt?`, `result`, `message?`, `recordsChanged` | Feeds the Data Sources screen |
| **DataSourceConfiguration** | `provider`, `isEnabled`, `settings` (non-secret JSON), `lastSuccessAt?`, `latestDataDate?` | Secrets are in Keychain, not here |
| **AlertRule** | `id`, `kind`, `target` (portfolio/scheme), `threshold`, `isEnabled`, `lastFiredAt?` | Kinds: daily move %, estimate vs official gap, stale data, new disclosure |

## As built (schema V1, watchlist)
- `WatchlistItem`: AMFI scheme code (unique), name, date added.
- `StoredNAV`: scheme code + valuation date (unique key), official NAV, retrieval time. Insert-only; one row per fund per day, written whenever the AMFI file is fetched. This is how NAV history builds up.
- AMFI's full NAV file is cached as `NAVAll.txt` next to the store and refreshed when older than 6 hours.
- Store: `Watchlist.store` in the app container's Application Support/FundScope. The earlier `FundScope.store` (which could hold personal amounts) is deleted on launch.
- The entities in the tables above that hold personal money (Portfolio, InvestmentAccount, InvestmentHolding, InvestmentTransaction, ImportRecord) are no longer planned.

## Disclosures (as built)
Saved as JSON, one file per fund per month: `Disclosures/<scheme code>/<yyyy-MM-dd>.json` next to the store. Files are never overwritten (a published month doesn't change), so importing the same month again keeps the original. Each holds `Disclosure` (fund code, date, holdings with ISIN, name, industry, asset type, % weight, quantity), plus the printed fund title, source file name and import time.

## End-of-day estimates (as built)
`Estimates/<yyyy-MM-dd>.json` next to the store, written once per trading day and never changed. Each `FrozenEstimate` holds fund code, valuation date, estimated NAV, baseline NAV, coverage, holdings date, model version, newest quote time and save time. Reconciliations aren't stored: they're worked out each time from frozen estimates plus stored official NAVs, so they always reflect the original estimate.

## Superseded: import-based schema (removed 2026-10-29)
`Portfolio`, `InvestmentAccount`, `FundScheme`, `InvestmentTransaction`, `InvestmentHolding` and `ImportRecord` exist, in `FundScopeCore/Store/StoreModels.swift`. Records link by ID strings (`accountID`, `schemeCode`, `importID`) rather than SwiftData relationships. That keeps undo-by-import a simple delete. `FundScheme.code` is the ISIN until AMFI codes arrive in Phase 3. The other entities are added in later schema versions.

## Relationships
```
Portfolio 1─* InvestmentAccount 1─* InvestmentHolding *─1 FundScheme
                                1─* InvestmentTransaction *─1 FundScheme
FundScheme 1─* OfficialNAV
FundScheme 1─* FundPortfolioSnapshot 1─* FundHolding *─0..1 Security
FundScheme 1─* EstimatedNAV
FundScheme 1─* NAVReconciliation
Security 1─* MarketQuote
ImportRecord 1─* InvestmentTransaction / InvestmentHolding
```

## Migrations
- Use `VersionedSchema` + `SchemaMigrationPlan` from the first release (`SchemaV1`).
- Every schema change adds a new version and a migration stage, with a test that opens a V(n-1) store fixture.
- Before a migration runs, copy the store file to `~/Library/Application Support/FundScope/Backups/` with a date stamp, keeping the last 5.

## Store locations
- Real: `~/Library/Application Support/FundScope/FundScope.store`
- Demo: `~/Library/Application Support/FundScope/Demo.store`
- Raw imported files are **not** copied; only the file name and SHA256 hash are kept.
