# 10 — Calculation engine

All of this lives in `FundScopeCore/Engine` as pure functions on value types. Input in, output out. No database, network or `Date()` inside. Every function is tested with hand-calculated fixtures.

## 1. Estimated live NAV

### Model v1
```
EstimatedNAV(D, t) = BaselineNAV × (1 + R(t))

BaselineNAV = latest official NAV for this exact scheme+plan on the last trading day before D

R(t) = Σ_priced  w_i × r_i(t)        ← priced equity
     + Σ_residual w_j × r_j          ← cash / debt / other, see table
     (weights w as decimals, from the latest usable disclosure)

r_i(t) = P_i(t) / PrevClose_i − 1
```

### Inputs and how each asset type is handled
| Asset | v1 treatment | Shown as |
|-------|-------------|----------|
| Indian listed equity with a live quote | `r_i` from quote | Priced |
| Indian listed equity, no quote / stale > 5 min in market hours | Excluded from priced sum; weight counted as **unpriced** | Warning |
| Cash, TREPS, net receivables | r = 0 | Residual (flat) |
| Debt, G-secs, T-bills | r = 0 (accrual ignored in v1) | Residual (flat) |
| Hedged pairs (arbitrage stock + its short future) | r = 0 | Residual (flat) |
| ETF units (e.g. a gold ETF) with an NSE symbol and a live quote (v1.1) | `r_i` from quote, ISIN → symbol via NSE `eq_etfseclist.csv` | Priced |
| Liquid, money-market and overnight fund units, matched by name (v1.1) | r = 0 | Residual (flat) |
| Derivatives (futures/options) | Not modelled | **Unsupported** |
| Foreign equity, international FoF | Not modelled | **Unsupported** |
| Other MF units, REIT/InvIT | Not modelled. NSE publishes no REIT/InvIT ISIN list, and name matching isn't allowed without confirmation | Unsupported |

Unpriced weight is **not silently ignored**. v1 rule: unpriced equity is assumed to move with the priced equity average (`r_unpriced = Σ w_i r_i / Σ w_i`), and the coverage meter shows how much weight that assumption covers. This is a stated assumption, stored with the model version.

### Coverage and when not to estimate
- `pricedWeight` = weight with real quotes. `unsupportedWeight` = derivatives + foreign + other.
- Coverage ≥ 90% → normal. 75–90% → warning colour. < 75% or unsupportedWeight > 10% → **"Not estimable"**, no number shown.
- Nothing priced → "Not estimable", unless the fund holds hedged pairs and has no unpriced stocks. An arbitrage fund gets a flat (0%) estimate; an all-debt fund stays not estimable.
- v1.1 (2026-10-29): non-stock listed holdings keep their ISIN at import, ETFs are priced, cash-like fund units are flat, and arbitrage funds get flat estimates.
- Category gate (`SchemeRecord.isEstimableCategory`): only AMFI "Equity Scheme" and "Hybrid Scheme" funds are candidates. Debt, liquid, FoF, index and ETF schemes are not estimated. Hybrid funds were added in v1.1, and the coverage rules above decide whether each one is estimated.

### Getting the baseline right
- `PrevClose_i` must be the exchange's previous close for **the same day as the baseline NAV**. Use the exchange-reported previous close from the quote (it is already adjusted for splits/bonuses), not our own stored close.
- Holidays: baseline = last date with an official NAV. If D-1 was a holiday, prev close and baseline NAV both refer to the last trading day, so they still match.
- If the official NAV for the last trading day is not out yet (morning after a late AMFI publish), the baseline is one day older. Then `r_i` must also be measured from that older close: `P_i(t) / Close_i(baseline date) − 1`. If that close is not available, the estimate is **not shown**.
- Plans: Direct and Regular hold the same portfolio but have different NAVs. Apply `R(t)` to each plan's own baseline NAV.

### Corporate actions
- Using the exchange's adjusted previous close handles splits, bonuses and rights in `r_i`.
- Disclosure weights are not affected by splits (weights are % of NAV).
- Quantity-based comparisons (Portfolio Changes) must adjust quantities for splits/bonuses between the two disclosure dates; until a corporate action source exists, flag quantity changes of exactly 2×, 5×, 10× (or 1/2, 1/5…) as "possible split/bonus".

### Avoiding look-ahead bias
- A disclosure for month M is published around the 10th of month M+1. When computing or back-testing an estimate for date D, only use disclosures with `importedAt`/`publishedAt` ≤ D. Store `publishedAt` (user can edit; default = import date).
- Reconciliation must use the estimate as it was frozen, not a recomputed one.

### Model versioning
- `modelVersion` string, e.g. `"v1.1-flat-residual"` (v1.0 until 2026-10-29). Saved with every `EstimatedNAV` and `NAVReconciliation`.
- A new version never rewrites old rows. Accuracy screens can filter or compare by version.

### Planned v2 improvements (only after v1 has 30+ reconciled days)
- Drift-adjust weights from disclosure date to baseline date using price changes.
- Daily expense ratio deduction (TER/365).
- Debt accrual at a yield estimate.
- Index futures handled via index quote.

## 2. Intraday snapshots and the end-of-day freeze
- In memory: latest estimate per fund, updated on each tick batch (≤ 1/s).
- Saved: one `EstimatedNAV` row per fund per minute (`isFinal = false`), kept 30 days.
- Freeze: after market close, save one `isFinal = true` row per fund per date, using last traded prices. Note: NSE's official close is a VWAP of the last 30 minutes, so last-traded price can differ slightly; this is a known source of error. The freeze time is a setting (default 15:35 IST).
- Never overwritten, even if computed again later.

## 3. Reconciliation and accuracy
When official NAV for (scheme, D) arrives and a final estimate exists:
```
absError = Estimated − Official
pctError = absError / Official × 100
```
Stored in `NAVReconciliation` with model version, holdings date and coverage.

Accuracy stats per fund and overall, over a chosen range: count, mean absolute % error (MAPE), median absolute % error, worst (largest absolute), trend (last 30 days vs previous 30), share of days within ±0.25%.

Wording rules: fewer than 30 reconciled days → "Not enough history". Never call the model "highly accurate"; show the numbers.

## 4. Portfolio valuation
- Official value per holding = units × official NAV (latest date) — show that date.
- Estimated value = units × estimated NAV (only for estimable funds; otherwise use official value and mark it).
- Estimated day P&L = Σ units × (EstimatedNAV − BaselineNAV).
- Units come from transactions when history exists, else from the holdings snapshot.

## 5. Value history (cash-flow aware)
For each day d: `value(d) = Σ_funds units_held(d) × NAV(d)` and `netInvested(d) = Σ purchases − Σ redemptions up to d`. The chart shows both lines so new money is not mistaken for return.

## 6. XIRR
- Cash flows: purchase/SIP/switch-in = negative (money in); redemption/IDCW payout/switch-out = positive; final value at valuation date = positive. IDCW reinvest: no cash flow (units increase only).
- Portfolio-level: switches between two funds in the same portfolio cancel out; keep them only at fund level.
- Solve `Σ CF_k / (1+x)^((d_k − d_0)/365) = 0` with Newton–Raphson from 0.1, fall back to bisection on [−0.99, 10].
- Return `nil` (shown "—") if there are no sign changes, fewer than 2 flows, or no convergence.
- Holding period < 1 year: still compute, label "annualised; short period".
- Test against spreadsheet `XIRR()` outputs.

## 7. Look-through exposure
```
exposure(company c) = Σ_funds  value_f × w_{f,c}
```
- `value_f` = my current value in fund f (official or estimated, chosen by toggle).
- Weights from each fund's latest disclosure (show its date).
- Groups: by company (ISIN), sector, market-cap bucket.
- Unmapped holdings (no ISIN match) and unsupported assets are separate buckets. Totals always add to 100%.
- Concentration: top-10 share and Herfindahl index (Σ share²).

## 8. Fund overlap
`overlap(A, B) = Σ_c min(w_{A,c}, w_{B,c})` over companies held by both (weights in %). Matrix for all pairs of selected funds.

## 9. Disclosure diff
Between snapshots S1 (older) and S2 (newer) of the same fund:
- New: in S2 not S1. Exited: in S1 not S2.
- Increased/decreased: by weight change, and by quantity change when quantities exist in both.
- Label: "Confirmed quantity change" vs "Weight change only — may be price movement".
- Sector change: Σ weights by sector, S2 − S1. Concentration change: top-10 share and HHI.

## Engine test fixtures (must exist before the code)
- 3-stock fund with known weights and prices → known NAV estimate (worked by hand in the test comment).
- Fund with 5% cash, 3% unpriced, 2% derivatives → expected coverage and treatment.
- Holiday between baseline and today.
- Split: prev close adjusted.
- XIRR cases from a spreadsheet, including a case that does not converge.
- Overlap of two funds with 2 common stocks.
