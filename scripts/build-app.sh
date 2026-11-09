#!/usr/bin/env bash
# Builds dist/TwinKeys.app (universal: arm64 + x86_64) and a zip for release.
# Runs on macOS with Xcode. Usage: scripts/build-app.sh [version] [build-number]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-$(tr -d '[:space:]' < VERSION)}"
BUILD="${2:-1}"
APP="dist/TwinKeys.app"

swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/TwinKeys" "$APP/Contents/MacOS/TwinKeys"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

# App icon: use the .icns from Resources if present, otherwise build it from the 1024 px PNG.
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
else
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d Resources/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi
cp Resources/mapping.default.json "$APP/Contents/Resources/mapping.default.json"
# In-app help (works offline).
mkdir -p "$APP/Contents/Resources/help"
cp docs/help/en.md docs/help/ja.md "$APP/Contents/Resources/help/"
# Localized Info.plist strings (English / Japanese). Their presence also tells macOS the app supports both.
for l in en ja; do
  mkdir -p "$APP/Contents/Resources/$l.lproj"
  cp "Resources/$l.lproj/InfoPlist.strings" "$APP/Contents/Resources/$l.lproj/"
  plutil -lint "$APP/Contents/Resources/$l.lproj/InfoPlist.strings"
done
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"

# Ad-hoc signature (no certificate). Not notarized: see README for first launch.
codesign --force --deep --sign - "$APP"
codesign --verify --verbose "$APP"
lipo -info "$APP/Contents/MacOS/TwinKeys"

ditto -c -k --keepParent "$APP" "dist/TwinKeys-$VERSION-universal.zip"
echo "Built $APP and dist/TwinKeys-$VERSION-universal.zip"
