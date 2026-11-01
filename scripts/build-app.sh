#!/bin/zsh
# Builds Dever and packages it as Dever.app (ad-hoc signed).
# DMG=1 ./scripts/build-app.sh  → also produces build/Dever.dmg to share.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-release}
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Dever"

APP=build/Dever.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Dever"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Dever</string>
  <key>CFBundleDisplayName</key><string>Dever</string>
  <key>CFBundleIdentifier</key><string>io.github.eri.dever</string>
  <key>CFBundleExecutable</key><string>Dever</string>
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

codesign --force --deep --sign - "$APP"
echo "→ $APP"

if [[ "${DMG:-0}" == "1" ]]; then
  rm -f build/Dever.dmg
  hdiutil create -volname Dever -srcfolder "$APP" -ov -format UDZO build/Dever.dmg >/dev/null
  echo "→ build/Dever.dmg"
fi
