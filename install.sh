#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "╔══════════════════════════════════╗"
echo "║      Input Switcher Kurulum      ║"
echo "╚══════════════════════════════════╝"
echo ""

# Apple Silicon kontrolü
ARCH=$(uname -m)
if [ "$ARCH" != "arm64" ]; then
    echo -e "${RED}Hata: Bu uygulama sadece Apple Silicon (M1/M2/M3/M4) destekler.${NC}"
    exit 1
fi

# Xcode Command Line Tools kontrolü
if ! command -v swiftc &> /dev/null; then
    echo -e "${YELLOW}Xcode Command Line Tools kuruluyor...${NC}"
    xcode-select --install
    echo "Kurulum tamamlandığında bu scripti tekrar çalıştırın."
    exit 0
fi

echo -e "${GREEN}✓ Swift derleyici hazır${NC}"

m1ddc_path() {
    if [ -x "/opt/homebrew/bin/m1ddc" ]; then
        echo "/opt/homebrew/bin/m1ddc"
        return
    fi

    if [ -x "/usr/local/bin/m1ddc" ]; then
        echo "/usr/local/bin/m1ddc"
        return
    fi

    if command -v m1ddc >/dev/null 2>&1; then
        command -v m1ddc
        return
    fi
}

# m1ddc kurulumu
if [ -z "$(m1ddc_path)" ]; then
    echo ""
    echo -e "${YELLOW}m1ddc kuruluyor...${NC}"

    if command -v brew >/dev/null 2>&1; then
        brew install m1ddc >/dev/null 2>&1 || true
    fi

    if [ -z "$(m1ddc_path)" ]; then
        TMPDIR=$(mktemp -d)
        cd "$TMPDIR"

        git clone https://github.com/waydabber/m1ddc.git 2>/dev/null
        cd m1ddc
        make 2>/dev/null

        sudo mkdir -p /usr/local/bin
        sudo cp m1ddc /usr/local/bin/

        cd ~
        rm -rf "$TMPDIR"
    fi

    if [ -z "$(m1ddc_path)" ]; then
        echo -e "${RED}Hata: m1ddc kurulamadı.${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ m1ddc kuruldu: $(m1ddc_path)${NC}"
else
    echo -e "${GREEN}✓ m1ddc zaten kurulu: $(m1ddc_path)${NC}"
fi

# Swift dosyasının konumu
SWIFT_FILE="$SCRIPT_DIR/InputSwitcher.swift"
VERSION_FILE="$SCRIPT_DIR/VERSION"

chmod +x "$SCRIPT_DIR/install.command" "$SCRIPT_DIR/install.sh" "$SCRIPT_DIR/build_app.sh"

if [ ! -f "$SWIFT_FILE" ]; then
    echo -e "${RED}Hata: InputSwitcher.swift bulunamadı: $SWIFT_FILE${NC}"
    exit 1
fi

if [ ! -f "$VERSION_FILE" ]; then
    echo -e "${RED}Hata: VERSION bulunamadı: $VERSION_FILE${NC}"
    exit 1
fi

APP_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [ -z "$APP_VERSION" ]; then
    echo -e "${RED}Hata: VERSION dosyası boş.${NC}"
    exit 1
fi

# Uygulama klasörü
APP_DIR="$HOME/Applications"
mkdir -p "$APP_DIR"

APP_BUNDLE="$APP_DIR/InputSwitcher.app"

echo ""
"$SCRIPT_DIR/build_app.sh" >/dev/null
BUILT_APP_BUNDLE="$SCRIPT_DIR/build/InputSwitcher.app"

if [ ! -d "$BUILT_APP_BUNDLE" ]; then
    echo -e "${RED}Hata: Derleme başarısız oldu.${NC}"
    exit 1
fi

if pgrep -f "$APP_BUNDLE/Contents/MacOS/InputSwitcher" > /dev/null; then
    echo -e "${YELLOW}Çalışan eski sürüm kapatılıyor...${NC}"
    pkill -f "$APP_BUNDLE/Contents/MacOS/InputSwitcher" || true
    sleep 1
fi

if [ -d "$APP_BUNDLE" ]; then
    echo -e "${YELLOW}Mevcut kurulum güncelleniyor...${NC}"
    rm -rf "$APP_BUNDLE"
fi

ditto "$BUILT_APP_BUNDLE" "$APP_BUNDLE"

if command -v xattr >/dev/null 2>&1; then
    xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true
fi

echo -e "${GREEN}✓ Input Switcher v$APP_VERSION kuruldu${NC}"

# Login item ekleme seçeneği
echo ""
read -p "Oturum açıldığında otomatik başlasın mı? (e/h): " AUTOSTART
if [[ "$AUTOSTART" =~ ^[Ee]$ ]]; then
    osascript -e "tell application \"System Events\" to make login item at end with properties {path:\"$APP_BUNDLE\", hidden:true}" 2>/dev/null && \
        echo -e "${GREEN}✓ Login item eklendi${NC}" || \
        echo -e "${YELLOW}⚠ Login item eklenemedi, manuel olarak ekleyebilirsiniz${NC}"
fi

echo ""
echo "╔══════════════════════════════════╗"
echo "║         Kurulum Tamamlandı!      ║"
echo "╚══════════════════════════════════╝"
echo ""
echo -e "Uygulama konumu: ${GREEN}$APP_BUNDLE${NC}"
echo -e "Sürüm: ${GREEN}$APP_VERSION${NC}"
echo ""
echo "Şimdi başlatmak için:"
echo -e "  ${YELLOW}open '$APP_BUNDLE'${NC}"
echo ""

read -p "Şimdi başlatılsın mı? (e/h): " LAUNCH
if [[ "$LAUNCH" =~ ^[Ee]$ ]]; then
    open "$APP_BUNDLE"
    echo -e "${GREEN}✓ Input Switcher başlatıldı — menü barını kontrol edin 🖥${NC}"
fi
