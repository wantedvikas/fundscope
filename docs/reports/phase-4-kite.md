# Phase 4 report — Kite Connect live prices — 2026-10-29

## Implemented
- **`Kite`** (Core): login URL with a state check, request-token extraction (failed or cancelled login and a mismatched state are rejected), checksum, token exchange, logout, `/quote` in batches of 500 with 1-second spacing, and error mapping (403 `TokenException` → reconnect, 429 → rate-limited, Kite error envelope → message). There is no order code.
- **`NSESymbols`:** ISIN → NSE symbol from NSE's public equity list, cached and refreshed weekly.
- **`LoginCallback`:** a one-shot listener on 127.0.0.1:7313 that catches Zerodha's redirect. Paste-the-address fallback.
- **`Keychain`:** device-only, unlocked-only storage for key, secret and token. UI tests use a separate service name.
- **App:**
  - Settings → Zerodha: save key and secret; copy the redirect URL; Connect/Reconnect; paste fallback; Refresh Prices; Disconnect; Replace (logs out first).
  - Prices refresh once a minute during market hours, once at launch, and after adding funds or holdings. Each refresh is also stored as a sample for the intraday chart.
  - An expired session switches to "Requires authentication".
  - Data Sources shows Kite's real status.
- **Estimates:** live estimates now work in your watchlist (they need imported holdings plus prices). An estimate is refused when the official NAV isn't for the trading day before the session; it says "Official NAV for … isn't published yet" rather than mixing days. `MarketCalendar.sessionDay(at:)` is shared by demo and real data.

## Tests run
- `swift test` → **69 passed**. New tests:
  - checksum (known SHA-256), login URL encoding, redirect state, failed or cancelled logins;
  - session request shape (the secret itself is never sent), quote request headers;
  - quote parsing: missing stocks skipped, a zero price rejected, exchange timestamp read;
  - 403, 429 and InputException mapping;
  - NSE list parsing (real rows), Keychain round trip under a throwaway service name;
  - the loopback listener catching a real local HTTP request;
  - a real-mode estimate (+1.90% from a +2% stock at 95%) and refusal when the official NAV is a day behind.
- Build: 0 errors, 0 warnings. UI tests not re-run: the Settings tab isn't covered by them, and they need the Mac to be free.

## Verified with the real service (29 Oct 2026, ~15:50 IST, after market close)
- The developer console accepted `http://127.0.0.1:7313/kite`, and the Connect plan shows live quotes; the Personal plan doesn't.
- Zerodha login → local listener caught the redirect → token exchange succeeded. Key, secret and token are in the Keychain; checked for presence only, values never read.
- The NSE equity list downloaded and was cached (185 KB).
- After importing Parag Parikh Flexi Cap holdings, Settings → Zerodha showed live prices from `/quote` (confirmed on the developer's Mac).
- **Still to see:** prices moving through a market session and a live estimate for a fund with only Indian stocks. Parag Parikh is "Not estimable" by rule.

## Known limitations
- REST polling once a minute, not WebSocket streaming.
- Only Indian stocks are priced. Foreign stocks, REITs and fund units count as unsupported, so Parag Parikh Flexi Cap stays "Not estimable" (over 10% of the fund).
- Intraday chart samples are kept in memory only, so they reset if the app restarts mid-session.
- Ad-hoc signed builds may lose Keychain access after updates; you'll be asked to reconnect or re-enter the key.

## Next steps
1. You: create a Kite Connect app, set the redirect URL, enter the key and secret, connect during market hours. I then verify against the real service.
2. Phase 6: freeze the end-of-day estimate and reconcile it with the official NAV (NAV Accuracy).
