#!/bin/bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWIFT_FILE="$SCRIPT_DIR/InputSwitcher.swift"
VERSION_FILE="$SCRIPT_DIR/VERSION"
BUILD_DIR="$SCRIPT_DIR/build"
APP_BUNDLE="$BUILD_DIR/InputSwitcher.app"

# Apple Silicon kontrolü
if [ "$(uname -m)" != "arm64" ]; then
    echo -e "${RED}Hata: Bu uygulama sadece Apple Silicon (M1/M2/M3/M4) destekler.${NC}" >&2
    exit 1
fi

if ! command -v swiftc &> /dev/null; then
    echo -e "${RED}Hata: swiftc bulunamadı. Xcode Command Line Tools kurun: xcode-select --install${NC}" >&2
    exit 1
fi

if [ ! -f "$SWIFT_FILE" ]; then
    echo -e "${RED}Hata: InputSwitcher.swift bulunamadı: $SWIFT_FILE${NC}" >&2
    exit 1
fi

if [ ! -f "$VERSION_FILE" ]; then
    echo -e "${RED}Hata: VERSION bulunamadı: $VERSION_FILE${NC}" >&2
    exit 1
fi

APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [ -z "$APP_VERSION" ]; then
    echo -e "${RED}Hata: VERSION dosyası boş.${NC}" >&2
    exit 1
fi

MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo -e "${YELLOW}Uygulama derleniyor... (v$APP_VERSION)${NC}"

swiftc "$SWIFT_FILE" \
    -o "$MACOS_DIR/InputSwitcher" \
    -framework Cocoa \
    -framework Foundation \
    -framework Network \
    2>&1

echo -e "${GREEN}✓ Derleme tamamlandı${NC}"

# Info.plist oluştur
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>InputSwitcher</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.inputswitcher</string>
    <key>CFBundleName</key>
    <string>Input Switcher</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSLocalNetworkUsageDescription</key>
    <string>Input Switcher needs local network access to discover the other Mac and send monitor switch requests.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_inputswitcher._tcp</string>
    </array>
</dict>
</plist>
PLIST

echo -e "${GREEN}✓ App bundle hazırlandı${NC}"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
fi

echo "$APP_BUNDLE"
