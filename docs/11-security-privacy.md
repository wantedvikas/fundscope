# 11 — Security and privacy

## Principles
- FundScope stores only the names/codes of funds you watch and their public NAVs. It never stores units, amounts, returns or account identifiers (decision D7).
- All data stays on this Mac. No server, no cloud sync, no analytics, no crash reporting SDK.
- FundScope never asks for or sees the Zerodha password, PIN or TOTP. Login happens on Zerodha's own web page.
- Read-only: no order placement, SIP changes, or fund transfers. The Kite module contains no code for these.
- No unauthorised scraping.

## Secrets
| Secret | Where | Notes |
|--------|-------|-------|
| Kite `api_key` | Keychain | Entered by the user in Settings |
| Kite `api_secret` | Keychain | Entered by the user; used only for the session checksum |
| Kite `access_token` | Keychain | Replaced daily; deleted on Disconnect |

- Keychain item class `kSecClassGenericPassword`, service `com.<you>.FundScope`, accessible `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (not synced to iCloud).
- Never in source, `Info.plist`, `UserDefaults`, SwiftData, logs, crash output or test fixtures.
- The secret fields in Settings are `SecureField`s and never show the stored value again (only "Saved · Replace").
- `.gitignore` excludes `*.xcconfig.local`, `Fixtures/private/`, and any `.env`.

## Distribution to family Macs (decision D5)
- No paid Apple Developer Program. Release builds are signed locally (ad-hoc, "Sign to Run Locally") with hardened runtime and App Sandbox on. They are **not notarised**.
- Copy the `.app` to a family Mac (zipped, AirDrop or USB). On first launch macOS blocks it. Approve it once in System Settings → Privacy & Security → **Open Anyway**. Repeat after every update, because each build has a new signature.
- Don't tell family members to turn off Gatekeeper or run `xattr` commands. The one-time **Open Anyway** is the supported route.
- Keychain caveat: each ad-hoc build has a different signature, so after an update macOS may ask to allow FundScope access to its saved Kite items, or the person may need to re-enter the Kite key and secret. Phase 4 must handle a missing or inaccessible Keychain item by showing "Requires authentication", never by crashing.
- Optional free alternative: build from source in Xcode on each Mac with a free Apple ID ("Personal Team"). This isn't needed for the plan above.
- Make the build with `scripts/make-family-build.sh` (output `build/Family/FundScope.zip`, universal Intel + Apple Silicon). It bundles this Mac's watchlist (fund codes in order), the imported AMC disclosures and a copy of AMFI's `NAVAll.txt` as `StarterFunds.json` + `NAVAll.txt`. On a Mac with an empty watchlist that hasn't finished onboarding, FundScope saves those disclosures, adds the funds and skips onboarding. It then refreshes NAVs from AMFI and downloads history as usual. A Mac that already has a watchlist ignores the bundle.
- The binary contains no keys, tokens, amounts or account data: only which funds are watched and their public disclosures. Each person sets up their own Kite credentials on their own Mac.
- `BUNDLE_ID=com.vikasghodke.FundScope.familytest scripts/make-family-build.sh` makes a test copy with its own sandbox container and Keychain service. Use it to check first-launch seeding without touching the real data.
- Each Mac has its own local store; nothing is shared or synced between family Macs.
- No auto-updater in v1 (it would add a network endpoint and signing infrastructure).

## Kite login (as built)
- Key, secret and access token are stored in the Keychain only (service `com.vikasghodke.FundScope.kite`, `WhenUnlockedThisDeviceOnly`). The secret is never sent; only the SHA-256 checksum is.
- Login happens on Zerodha's own page in your browser. FundScope waits for the redirect with a one-shot listener bound to **127.0.0.1:7313** (it can't be reached from other machines), answers one request and stops after 5 minutes at most. A random `state` must match, so a stray request can't inject a token. Requires the `network.server` sandbox entitlement.
- Kite receives the NSE symbols of the stocks held by your watched funds. NSE receives a plain GET for its public equity list.
- Disconnect calls `DELETE /session/token` before removing the token.

## Local data
- Stored under `~/Library/Application Support/FundScope/`, protected by macOS file permissions and FileVault.
- App Sandbox on, with only the entitlements needed: outgoing network, user-selected files (read-only), and app group (if the menu bar extra needs a separate process; otherwise none).
- Imported files are read, not copied. Only file name and hash are kept.
- Client IDs: only the last 4 characters are stored.
- "Delete all data" in Settings removes stores, backups and Keychain items, with double confirmation.

## Logging
- `os.Logger` with `privacy: .private` for any amount, unit, ISIN-to-person link, token or account value.
- Never log request headers or URLs that contain tokens.
- No log files are written outside the system log.

## Network
- HTTPS only (ATS on). Hosts allowed: `api.kite.trade`, `ws.kite.trade`, `kite.zerodha.com` (login), AMFI host(s). Anything else needs a doc change first.
- Local callback listener (if used for Kite login) binds to `127.0.0.1` only, accepts one request, checks the `state` value, then closes.

## What each provider receives
| Provider | Sent |
|----------|------|
| Zerodha Kite | API key, access token, session checksum, instrument tokens subscribed. Zerodha already holds your account data |
| AMFI | A plain GET for the full public NAV file, identical for everyone. NAV history requests do include the scheme codes of funds you watch (one request per fund), so AMFI could see which public funds are being looked up from your IP address. No amounts or identity are sent |
| AMC sites | Nothing (files are downloaded by you in the browser) |
| Others | Nothing |

## Threats considered
| Threat | Mitigation |
|--------|-----------|
| Secret leaks into git | Keychain only; `.gitignore`; pre-commit grep for `api_secret` patterns |
| Token stolen from disk | Keychain, device-only, when-unlocked |
| Malformed or malicious import file | Parse as data only; size limit (50 MB); no formula evaluation; XLSX read without macros |
| Fake values shown after provider failure | Providers return errors, never placeholder values; UI shows stale state |
| Demo data mixed into real data | Separate store files |
