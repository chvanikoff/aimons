#!/bin/bash
# Build AIMon as a distributable .app inside a .dmg.
#
# Produces dist/AIMon.app (a menu-bar agent: LSUIElement, ad-hoc signed) and dist/AIMon-<ver>.dmg
# with a drag-to-Applications layout. Ad-hoc signing means Gatekeeper will warn on first open for
# anyone who downloads it (right-click → Open, once) — see the note printed at the end.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="AIMon"
BUNDLE_ID="io.romanc.aimon"
VERSION="$(sed -n 's/.*version = "\(.*\)".*/\1/p' Sources/AIMonCore/Version.swift)"
VERSION="${VERSION:-0.1.0}"
DIST="dist"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/$APP_NAME-$VERSION.dmg"

echo "▶ building release binary…"
swift build -c release --product "$APP_NAME"
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"

echo "▶ assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"

echo "▶ generating app icon…"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
MASTER="$(mktemp -d)/icon.png"
"$BIN" --app-icon "$MASTER" >/dev/null
for s in 16 32 128 256 512; do
  sips -z "$s" "$s"         "$MASTER" --out "$ICONSET/icon_${s}x${s}.png"     >/dev/null
  sips -z $((s*2)) $((s*2)) "$MASTER" --out "$ICONSET/icon_${s}x${s}@2x.png"  >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "▶ writing Info.plist…"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Roman Chvanikov</string>
</dict>
</plist>
PLIST

echo "▶ ad-hoc signing…"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "  signature OK"

echo "▶ building ${DMG}…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo ""
echo "✅ done → $DMG"
echo ""
echo "Distribution note: this build is ad-hoc signed (no paid Apple Developer ID), so the first"
echo "time a friend opens it macOS will say it's from an unidentified developer. They should"
echo "right-click the app → Open → Open (once). Or run: xattr -dr com.apple.quarantine /Applications/$APP_NAME.app"
