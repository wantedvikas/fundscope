# 09 — Adding funds (replaces Zerodha import)

> The Zerodha Coin/Console import described in earlier versions of this file was **removed** on 2026-10-29 (decision D7). FundScope no longer reads or stores units, amounts, transactions or account details.

## How funds are added
1. **Search:** type any part of a name. Matching uses AMFI's scheme list and understands short forms ("ICICI Pru", "WOC", "PPFAS", "Smallcap"). The default is Direct plan, Growth option, since that's what Zerodha Coin offers; Regular is one click away.
2. **Paste a list:** one name per line. Each name is matched and shown for confirmation. Names that aren't clear say "Pick one" and offer alternatives.
3. **From a file:** drop a holdings CSV or XLSX (Coin, Console, Tickertape…). Only the *Fund Name / Scheme Name* column and the *Plan Type* column are read. Every other column is ignored and nothing from the file is kept.

Code: `FundScopeCore/Providers/AMFI.swift` (`AMFI.parse`, `FundMatcher`, `FundListReader`) and `FundScopeCore/Import/TableReaders.swift` (CSV/XLSX).

## Verified
- 19 sample fund names, short forms included, resolve to the correct AMFI Direct Growth scheme (unit test `FundMatcherTests`, using a 78-line slice of the real 28 Oct 2026 AMFI file with Regular, IDCW and look-alike distractors).
- A Coin/Tickertape holdings export layout (header on row 4, "Total" row at the end) is read correctly. The test fixture has every number replaced by 0.
