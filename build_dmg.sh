#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"
APP_BUNDLE="$SCRIPT_DIR/build/InputSwitcher.app"
DIST_DIR="$SCRIPT_DIR/dist"

if [ ! -f "$VERSION_FILE" ]; then
    echo "VERSION dosyası bulunamadı."
    exit 1
fi

APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

chmod +x "$SCRIPT_DIR/build_app.sh" "$SCRIPT_DIR/build_dmg.sh"
"$SCRIPT_DIR/build_app.sh"

mkdir -p "$DIST_DIR"

DMG_PATH="$DIST_DIR/InputSwitcher-$APP_VERSION.dmg"
ZIP_PATH="$DIST_DIR/InputSwitcher-$APP_VERSION.zip"
rm -f "$DMG_PATH" "$ZIP_PATH"

hdiutil create \
    -volname "Input Switcher $APP_VERSION" \
    -srcfolder "$APP_BUNDLE" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "DMG hazır: $DMG_PATH"
echo "ZIP hazır: $ZIP_PATH"
