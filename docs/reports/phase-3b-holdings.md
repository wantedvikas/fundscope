# Phase 3b report — Fund holdings import — 2026-10-29

## Implemented
- **`DisclosureParser`** (Core) reads SEBI-format monthly portfolio statements:
  - finds the table by its ISIN and "% to Net Assets" headers, and handles headers that wrap onto two lines;
  - takes the fund name and "as on" date from above the table;
  - reads each section heading to set the asset type;
  - accepts weights as fractions or percents, including "$0.00%" text;
  - stops at GRAND TOTAL;
  - warns when weights don't add up to 100% or there's no date;
  - handles workbooks with one sheet per fund.
- **New asset type `hedged`** for arbitrage positions. The model treats them as flat, since the stock and its short future cancel out.
- **`DisclosureStore`:** one JSON file per fund per month, never overwritten.
- **Dataset:** imported holdings for watched funds feed Holdings Analysis (equal weight), the Watchlist composition, Fund → Holdings, Holdings Changes, and the AMC row in Data Sources (shows how many funds are missing holdings).
- **No live prices → no estimate.** The Watchlist says "Needs prices" instead of showing a broken estimate.
- **Import sheet** (⇧⌘I, Watchlist → Import Holdings, or empty-state buttons):
  - drop one or more files; each sheet is matched to a watched fund by name, and you can change the match;
  - "Already imported" months are skipped;
  - shows holdings count, total weight and any warnings per sheet.

## Tests run
- `swift test` → **57 passed**. New tests:
  - **Real PPFAS Flexi Cap files (Aug and Sep 2026):** title, date, total ≈ 100%, every section's weight matches the file's own sub-totals, HDFC Bank 7.75% with sector and quantity, futures after GRAND TOTAL excluded, "<0.01%" rows stay tiny.
  - The month-to-month diff runs on the real files.
  - Under v1 rules the fund is "Not estimable": foreign stocks plus fund units are over 10%.
  - A percent-style layout with TREPS, the date formats, sheets with no table, and the store never overwriting a month.
  - Imported holdings reach the dataset, with only watched funds included.
- Build and test build: 0 errors, 0 warnings.
- `xcodebuild … -only-testing:FundScopeUITests test` → **6 passed**, including `testImportFundHoldings` (imports both real PPFAS months, then checks Holdings Analysis and Holdings Changes).
- **Fixes after reviewing the screenshots:**
  - **Holdings Changes:** now compares only stocks and REITs. Cash, debt, arbitrage and fund units roll over monthly (TREPS is renamed every month, CDs mature) and had produced "18 new / 32 exited" of noise. Real result: 0 new, 1 exited (Great Eastern Shipping), 14 increased (e.g. DLF +285% shares, Indus Towers +725%).
  - **Look-through:** foreign stocks (Alphabet, Meta, Microsoft, Amazon) now count as companies, not "Cash, debt & other".
  - **Header:** the screen title now reads "Holdings Changes", matching the sidebar.

## Known limitations
- **Import is manual.** You download each fund house's file yourself (only PPFAS offers direct links; the others block scripts or build links in JavaScript).
- **Only PPFAS's layout is verified.** HDFC, ICICI, Invesco, Nippon, WhiteOak, Bandhan and Abakkus files may need small parser fixes when you first import them.
- **No market-cap buckets yet:** look-through shows "Unclassified". AMFI publishes a half-yearly large/mid/small list that could fill this.
- **Parag Parikh Flexi Cap stays "Not estimable"** (foreign about 11.9%, fund units 0.6%) unless the rule changes when live estimates are built.

## Next steps
1. Import your other fund houses' files and fix any layout gaps.
2. Kite Connect for live prices, then live NAV estimates.
