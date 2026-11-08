# Fixtures

Put real export files from Zerodha here to check the importer against the actual formats.

- `Fixtures/private/` is ignored by git. Put files with your real data there.
- Before copying a file into this folder (outside `private/`), remove your name and client ID, and change amounts if you want.

Useful files:
- Console → Portfolio → Holdings → Mutual funds → Download (XLSX or CSV)
- Console → Reports → Tradebook → Segment: Mutual funds (CSV)

The synthetic fixtures used by the automated tests are in `Packages/FundScopeCore/Tests/FundScopeCoreTests/Fixtures/`.
