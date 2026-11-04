#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/Ada.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Ada" "$APP_DIR/Contents/MacOS/Ada"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
swift scripts/make-icon.swift "$PROJECT_DIR/.build/AppIcon.iconset"
iconutil -c icns "$PROJECT_DIR/.build/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --deep --entitlements Resources/Ada.entitlements --sign - "$APP_DIR"
echo "Hazır: $APP_DIR"
