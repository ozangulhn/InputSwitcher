#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_FILE="$SCRIPT_DIR/VERSION"
APP_BUNDLE="$HOME/Applications/InputSwitcher.app"
DIST_DIR="$SCRIPT_DIR/dist"

if [ ! -f "$VERSION_FILE" ]; then
    echo "VERSION dosyası bulunamadı."
    exit 1
fi

APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"

chmod +x "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/install.command" "$SCRIPT_DIR/build_dmg.sh"
printf 'h\nh\n' | "$SCRIPT_DIR/install.sh"

mkdir -p "$DIST_DIR"

DMG_PATH="$DIST_DIR/InputSwitcher-$APP_VERSION.dmg"
rm -f "$DMG_PATH"

hdiutil create \
    -volname "Input Switcher $APP_VERSION" \
    -srcfolder "$APP_BUNDLE" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "DMG hazır: $DMG_PATH"
