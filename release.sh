#!/bin/bash
# Yeni sürümü GitHub Release olarak yayınlar.
# Kullanım: ./release.sh [notlar.md]

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

fail() {
    echo -e "${RED}Hata: $1${NC}" >&2
    exit 1
}

NOTES_FILE="${1:-}"
if [ -n "$NOTES_FILE" ] && [ ! -f "$NOTES_FILE" ]; then
    fail "Notlar dosyası bulunamadı: $NOTES_FILE"
fi

[ -f VERSION ] || fail "VERSION dosyası bulunamadı."
APP_VERSION="$(tr -d '[:space:]' < VERSION)"
[ -n "$APP_VERSION" ] || fail "VERSION dosyası boş."
TAG="v$APP_VERSION"

command -v git >/dev/null 2>&1 || fail "git bulunamadı."
command -v gh >/dev/null 2>&1 || fail "GitHub CLI (gh) bulunamadı. Kurulum: brew install gh"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "Bu klasör bir git deposu değil."

if [ -n "$(git status --porcelain)" ]; then
    fail "Çalışma dizini temiz değil. Önce değişiklikleri commit edin."
fi

git remote get-url origin >/dev/null 2>&1 || fail "'origin' remote tanımlı değil. Örn: git remote add origin git@github.com:ozangulhn/InputSwitcher.git"
REPO_URL="$(git remote get-url origin)"

gh auth status >/dev/null 2>&1 || fail "gh oturumu açık değil. Önce 'gh auth login' çalıştırın."

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    fail "Etiket $TAG yerelde zaten var."
fi

if [ -n "$(git ls-remote --tags origin "refs/tags/$TAG")" ]; then
    fail "Etiket $TAG origin üzerinde zaten var."
fi

echo -e "${YELLOW}Paketler hazırlanıyor...${NC}"
"$SCRIPT_DIR/build_dmg.sh"

ZIP_PATH="dist/InputSwitcher-$APP_VERSION.zip"
DMG_PATH="dist/InputSwitcher-$APP_VERSION.dmg"
[ -f "$ZIP_PATH" ] || fail "ZIP bulunamadı: $ZIP_PATH"
[ -f "$DMG_PATH" ] || fail "DMG bulunamadı: $DMG_PATH"

echo ""
echo "Yayın özeti"
echo "  Sürüm   : $APP_VERSION"
echo "  Etiket  : $TAG"
echo "  Depo    : $REPO_URL"
echo "  Dosyalar: $ZIP_PATH, $DMG_PATH"
if [ -n "$NOTES_FILE" ]; then
    echo "  Notlar  : $NOTES_FILE"
else
    echo "  Notlar  : otomatik oluşturulacak (--generate-notes)"
fi
echo ""

read -p "Yayınlansın mı? (y/n): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[YyEe]$ ]]; then
    echo "İptal edildi."
    exit 0
fi

git tag "$TAG"
git push origin HEAD --tags

if [ -n "$NOTES_FILE" ]; then
    gh release create "$TAG" "$ZIP_PATH" "$DMG_PATH" --title "Input Switcher $APP_VERSION" --notes-file "$NOTES_FILE"
else
    gh release create "$TAG" "$ZIP_PATH" "$DMG_PATH" --title "Input Switcher $APP_VERSION" --generate-notes
fi

echo -e "${GREEN}✓ $TAG yayınlandı${NC}"
