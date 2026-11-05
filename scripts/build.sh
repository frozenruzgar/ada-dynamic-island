#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
python3 scripts/sync-localizations.py
swift build -c release --product Ada
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/Ada.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Ada" "$APP_DIR/Contents/MacOS/Ada"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
if [[ -d "$BIN_DIR/Ada_Ada.bundle" ]]; then
    ditto "$BIN_DIR/Ada_Ada.bundle" "$APP_DIR/Contents/Resources/Ada_Ada.bundle"
fi
for locale_dir in Sources/Ada/Resources/*.lproj; do
    locale_name="$(basename "$locale_dir")"
    mkdir -p "$APP_DIR/Contents/Resources/$locale_name"
    if [[ -f "$locale_dir/InfoPlist.strings" ]]; then
        cp "$locale_dir/InfoPlist.strings" "$APP_DIR/Contents/Resources/$locale_name/InfoPlist.strings"
    fi
done
swift scripts/make-icon.swift "$PROJECT_DIR/.build/AppIcon.iconset"
iconutil -c icns "$PROJECT_DIR/.build/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --options runtime --timestamp --entitlements Resources/Ada.entitlements --sign "$SIGN_IDENTITY" "$APP_DIR"
else
    codesign --force --entitlements Resources/Ada.entitlements --sign - "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"
"$APP_DIR/Contents/MacOS/Ada" --check-localization
echo "Ada $VERSION hazır: $APP_DIR"
