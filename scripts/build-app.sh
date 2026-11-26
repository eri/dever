#!/bin/zsh
# Builds Dever and packages it as Dever.app (ad-hoc signed).
# DMG=1 ./scripts/build-app.sh  → also produces build/Dever.dmg to share.
# CANARY=1 ./scripts/build-app.sh → build/Dever Canary.app: made-up data, its own settings, Keychain
# entry and folder, a yellow mark (see Sources/Dever/Support/Canary.swift).
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${CANARY:-0}" == "1" ]]; then
  NAME="Dever Canary"; BUNDLE_ID="io.github.eri.dever.canary"
else
  NAME="Dever"; BUNDLE_ID="io.github.eri.dever"
fi

CONFIG=${1:-release}
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Dever"

APP="build/$NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dever"
[[ -f assets/AppIcon.icns ]] || ./scripts/make-icon.sh
if [[ "${CANARY:-0}" == "1" ]]; then
  # The same icon, its mark canary yellow instead of lime.
  sed 's/#DAFA9C/#FFCC3D/' docs/brand/app-icon.svg > build/app-icon-canary.svg
  ICON_SVG=build/app-icon-canary.svg ICON_OUT=build/AppIcon-canary.icns ./scripts/make-icon.sh >/dev/null
  cp build/AppIcon-canary.icns "$APP/Contents/Resources/AppIcon.icns"
else
  cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>Dever</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -f config/dever.json ]]; then
  cp config/dever.json "$APP/Contents/Resources/dever.json"
else
  echo "⚠️  config/dever.json missing: Slack and Linear won't be able to connect (see docs/SETUP.md)" >&2
fi

# A stable signing identity keeps the same code identity across builds, so the
# Keychain "Always Allow" sticks. Ad-hoc signatures change on every build, which
# makes macOS ask for the Keychain password again after each update.
# Override with DEVER_SIGN_IDENTITY="<name or SHA-1>"; defaults to the first valid
# code-signing identity (e.g. a free "Apple Development" certificate from Xcode).
IDENTITY=${DEVER_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk 'NR==1 && $2 ~ /^[0-9A-F]{40}$/ {print $2}')}
if [[ -n "$IDENTITY" ]]; then
  codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
  echo "Signed with $(security find-identity -v -p codesigning | grep "$IDENTITY" | sed 's/.*"\(.*\)"/\1/' || echo "$IDENTITY")"
else
  echo "⚠️  No code-signing identity found: ad-hoc signing. macOS will ask for Keychain access after each rebuild (see docs/SETUP.md)." >&2
  codesign --force --deep --sign - "$APP"
fi
echo "→ $APP"

if [[ "${DMG:-0}" == "1" ]]; then
  rm -f build/Dever.dmg
  hdiutil create -volname Dever -srcfolder "$APP" -ov -format UDZO build/Dever.dmg >/dev/null
  echo "→ build/Dever.dmg"
fi
