# 04 — Design system

Built in Phase 1 **before** any screen. Every screen uses only these tokens and components. If a screen needs something new, add it here first, then use it.

Reference for craft (not for copying): Linear, Raycast, Things, professional trading terminals.

## Principles
1. **Native first.** System font, system materials, standard controls, standard sidebar and toolbar. Customise only where a standard control falls short.
2. **Density with calm.** Many numbers on screen, organised by alignment and typography rather than boxes.
3. **Hierarchy through type and space**, not through colour, shadows or cards.
4. **Honest data.** Estimated values look different from official ones; stale values show their age; unknown values show "—" with a reason on hover.
5. **Colour has meaning.** Green and red only for financial direction. Accent only for interaction and selection.

### Avoid
Big rounded cards everywhere · gradients · drop shadows on content · oversized numbers · illustrations · random accent colours · mobile-style layouts · modals where a sheet, popover or inspector works.

## Typography
System font (SF Pro). Monospaced digits (`.monospacedDigit()`) for every NAV, price, %, ₹ value and unit count, so columns line up.

| Token | SwiftUI base | Size / weight | Use |
|-------|-------------|---------------|-----|
| `screenTitle` | `.title2` | 22 / semibold | Page header title |
| `sectionTitle` | `.headline` | 13 / semibold | Section headings in a page |
| `cardTitle` | `.subheadline` | 11 / semibold, secondary colour, uppercase tracking +0.4 | Metric labels, group headings |
| `body` | `.body` | 13 / regular | General text |
| `secondary` | `.body` | 13 / regular, secondary colour | Supporting text |
| `table` | `.callout` | 12 / regular, mono digits | Table cells |
| `label` | `.caption` | 11 / medium | Badges, chips, column headers |
| `caption` | `.caption2` | 10 / regular, tertiary colour | Timestamps, footnotes |
| `metricValue` | custom | 22 / medium, mono digits | Summary metric numbers |
| `metricValueSmall` | custom | 15 / medium, mono digits | Inspector and menu bar numbers |

Use Dynamic Type-friendly text styles where possible; sizes above are macOS defaults.

## Spacing
Scale: **4, 8, 12, 16, 20, 24, 32, 40** (`Space.xxs … Space.xxxl`). No other values.

| Use | Token |
|-----|-------|
| Icon to label | 4 |
| Inside controls, row cells | 8 |
| Between related items | 12 |
| Inside sections | 16 |
| Page side padding | 20 or 24 |
| Between sections | 32 |
| Onboarding and empty states | 40 |

Table row height: 24 (compact) / 28 (default). Sidebar rows use the system default.

## Corner radius
| Token | Value | Use |
|-------|-------|-----|
| `Radius.small` | 4 | Badges, chips, tooltip |
| `Radius.medium` | 6 | Controls, drop zone, inline panels |
| `Radius.large` | 10 | Sheets/onboarding panels only |

## Colour (semantic)
Defined in an asset catalog with light and dark variants, and named by meaning.

| Token | Based on | Note |
|-------|----------|------|
| `textPrimary` | `.primary` / `labelColor` | |
| `textSecondary` | `secondaryLabelColor` | |
| `textTertiary` | `tertiaryLabelColor` | |
| `background` | `windowBackgroundColor` | Explicit, never transparent |
| `surfaceElevated` | `controlBackgroundColor` | Inspector, popovers |
| `borderSubtle` | `separatorColor` | 1 px hairlines |
| `accent` | System accent (respects user setting) | Interaction only |
| `positive` | Custom green, desaturated (dark: lighter) | Gains. Check ≥ 4.5:1 contrast for text |
| `negative` | Custom red, desaturated | Losses |
| `warning` | `systemOrange` | Stale data, low coverage |
| `disabled` | `disabledControlTextColor` | |
| `selected` | `selectedContentBackgroundColor` | Row selection |
| `estimated` | Accent at reduced opacity, or dashed lines | Marks estimated values |

Gains and losses always also show a sign (+ / −), so meaning never depends on colour alone.

### Official vs estimated
- **Official:** solid text, solid chart lines, label "Official · 28 Oct".
- **Estimated:** `≈` prefix or "Est." label, dashed chart line, `estimated` colour, plus a time ("Est. · 14:32").

## Charts (Swift Charts)
- Hairline grid in `borderSubtle`, horizontal lines only. No chart background fill.
- Axis labels in `caption`, mono digits.
- One line colour per series; at most 5 categorical colours from one palette, tested in light and dark.
- Hover shows a vertical rule and the shared `ChartTooltip`.
- Area fill only for the main portfolio value series, at ≤ 10% opacity.
- Missing data creates a gap in the line; do not draw a line across it.

## Motion
- Default: `.snappy` (about 0.2 s). Only for state changes (selection, inspector open, sheet).
- Numbers updating live: no counting animation; a short (0.6 s) background tint in positive/negative on change, disabled when Reduce Motion is on.
- No looping animations except the system progress indicator.

## Components

| Component | Purpose | Key states |
|-----------|---------|-----------|
| `SidebarSection` / `NavigationRow` | Grouped sidebar with SF Symbols | default, hover, selected, badge count |
| `PageHeader` | Title, subtitle, trailing toolbar items, data timestamp | normal, with demo badge |
| `ToolbarActions` | Standard toolbar buttons (Sync, Import, Inspector toggle) | enabled, disabled, busy |
| `MetricTile` | Label + value + delta + "Official/Est." tag | known, unknown ("—"), stale, loading |
| `MetricStrip` | Row of 4–6 `MetricTile`s separated by hairlines (no cards) | |
| `FinancialTable` | Wrapper around `Table`: sortable columns, right-aligned numbers, mono digits, context menu | empty, loading, error |
| `ValueText` | Formats ₹, %, NAV, units consistently (Indian grouping 1,00,000) | positive, negative, neutral, unknown, estimated |
| `SearchField` | `.searchable` or inline field | |
| `FilterBar` | Chips + segmented control | |
| `RangePicker` | 1M 3M 6M 1Y 3Y 5Y All | |
| `FundPicker` | Searchable popover to pick schemes | |
| `StatusDot` | Provider/market status | connected, updating, stale, auth needed, unavailable, import required |
| `MarketStatusBadge` | Open / Pre-open / Closed / Holiday | |
| `ConnectionCard` | Provider status row on Data Sources/Settings | |
| `EmptyState` | Icon (SF Symbol), title, explanation, one primary action | |
| `LoadingState` | Progress indicator or table skeleton rows | |
| `ErrorState` | What failed, why, Retry/Resolve | |
| `MissingValue` | "—" with tooltip explaining why | |
| `ChartTooltip` | Date, values, official/estimated tags | |
| `ImportDropZone` | Drag and drop + browse button | idle, hovering, invalid file, processing |
| `InspectorPanel` | `.inspector` contents with sections | |
| `ConfirmDialog` | `.confirmationDialog` wrapper for destructive actions | |
| `DemoBadge` | "Demo data" pill in headers and the menu bar | |
| `CoverageMeter` | Thin bar showing priced weight vs unpriced vs unsupported | ok, warning (< 90%), poor (< 75%) |

## App icon
- A white lens over a rising NAV line on a teal-to-deep-blue tile, with a green dot for the latest point. It uses the standard macOS 824/1024 grid.
- Generated by `scripts/make-app-icon.swift` into `FundScope/Assets.xcassets/AppIcon.appiconset`. To change it, edit the script and run `swift scripts/make-app-icon.swift`; don't hand-edit the PNGs.

## Number formatting
- Currency: `₹1,23,456.78` (Indian grouping, `en_IN`). Compact in tight spaces: `₹1.23 L`, `₹4.56 Cr`.
- NAV: 4 decimal places. Units: 3 decimal places. Percent: 2 decimal places with sign.
- Dates: `28 Oct 2026`; times in IST, `14:32`.

## Light and dark mode checklist (each screen)
- [ ] No hard-coded colours
- [ ] Positive and negative readable on both backgrounds
- [ ] Charts readable on both
- [ ] Selected row readable in both, focused and unfocused window
- [ ] Increase Contrast setting tested
