#!/bin/zsh
# Builds a Release FundScope for family Macs with this Mac's watchlist and imported holdings inside.
# It carries fund codes, public AMC disclosures and AMFI's NAV file: no amounts, no Kite keys or tokens.
# Output: build/Family/FundScope.zip. BUNDLE_ID=… builds a separately sandboxed test copy.
set -euo pipefail
cd "${0:A:h}/.."

BUNDLE_ID=${BUNDLE_ID:-com.vikasghodke.FundScope}
DATA="$HOME/Library/Containers/com.vikasghodke.FundScope/Data/Library/Application Support/FundScope"
OUT=build/Family
APP="$OUT/FundScope.app"

xcodebuild -project FundScope.xcodeproj -scheme FundScope -configuration Release -derivedDataPath build/DerivedData -destination "generic/platform=macOS" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" -quiet build
rm -rf "$OUT" && mkdir -p "$OUT"
cp -R build/DerivedData/Build/Products/Release/FundScope.app "$APP"

python3 -I - "$DATA" "$APP/Contents/Resources" <<'EOF'
import json, pathlib, sqlite3, sys
data, res = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
db = sqlite3.connect(f"file:{data / 'Watchlist.store'}?mode=ro", uri=True)
codes = [row[0] for row in db.execute("select ZCODE from ZWATCHLISTITEM order by ZADDEDAT")]
navs = (data / "NAVAll.txt").read_text()
amfi = {line.split(";", 1)[0] for line in navs.splitlines()}
missing = [c for c in codes if c not in amfi]
assert codes and not missing, f"watchlist empty or not in NAVAll.txt: {missing}"
disclosures = [json.loads(f.read_text()) for c in codes for f in sorted((data / "Disclosures" / c).glob("*.json"))]
(res / "StarterFunds.json").write_text(json.dumps({"codes": codes, "disclosures": disclosures}))
(res / "NAVAll.txt").write_text(navs)
covered = len({d["fundCode"] for d in disclosures})
print(f"Bundled {len(codes)} funds, {len(disclosures)} disclosures ({covered} funds with holdings)")
EOF

# Adding files breaks the signature; re-sign ad-hoc keeping the sandbox entitlements and hardened runtime.
codesign --force --sign - --preserve-metadata=entitlements,flags "$APP"
codesign --verify --strict "$APP"
ditto -c -k --keepParent "$APP" "$OUT/FundScope.zip"
echo "Ready: $OUT/FundScope.zip"
