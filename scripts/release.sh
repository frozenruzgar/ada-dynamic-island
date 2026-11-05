#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
# Local packages support Apple Silicon; Intel is not a tested release target.
if [[ -n "${NOTARY_PROFILE:-}" && ( -z "${SIGN_IDENTITY:-}" || "${SIGN_IDENTITY:-}" == "-" ) ]]; then
    echo "Noter onayı için SIGN_IDENTITY gerekir." >&2
    exit 1
fi
./scripts/build.sh
APP_DIR="$PROJECT_DIR/dist/Ada.app"
PACKAGE_NAME="Ada-$VERSION-AppleSilicon"
PACKAGE_PATH="$PROJECT_DIR/dist/$PACKAGE_NAME"
stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/ada-release.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$stage_dir/submission.zip"
    xcrun notarytool submit "$stage_dir/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_DIR"
    xcrun stapler validate "$APP_DIR"
fi
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$PACKAGE_PATH.zip"
mkdir "$stage_dir/image"
ditto "$APP_DIR" "$stage_dir/image/Ada.app"
ln -s /Applications "$stage_dir/image/Applications"
hdiutil create -volname Ada -srcfolder "$stage_dir/image" -format UDZO -ov "$PACKAGE_PATH.dmg"
if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$PACKAGE_PATH.dmg"
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    xcrun notarytool submit "$PACKAGE_PATH.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$PACKAGE_PATH.dmg"
    xcrun stapler validate "$PACKAGE_PATH.dmg"
else
    echo "Paket noter onayı olmadan oluşturuldu."
fi
hdiutil verify "$PACKAGE_PATH.dmg"
shasum -a 256 "$PACKAGE_PATH.zip" "$PACKAGE_PATH.dmg" > "$PACKAGE_PATH.sha256"
./scripts/make-cask.sh
echo "Hazır: $PACKAGE_PATH.zip ve $PACKAGE_PATH.dmg"
