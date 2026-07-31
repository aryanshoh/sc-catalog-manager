#!/bin/bash
# Готовит релиз авто-обновления для GitHub Releases:
#   1) собирает .app нужной версии (через build_app.sh)
#   2) архивирует его в zip
#   3) подписывает и генерирует appcast.xml (утилитой Sparkle generate_appcast;
#      приватный ключ берётся из Keychain автоматически)
#
# Использование:
#   GH_OWNER=you GH_REPO=catalog VERSION=1.2 BUILD=3 ./release.sh
#
# Результат в dist/updates/:  CatalogManager-<VERSION>.zip  и  appcast.xml
# Оба файла нужно загрузить в GitHub Release с тегом v<VERSION>.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# --- параметры (те же, что в build_app.sh; переопределяются из окружения) -----
GH_OWNER="${GH_OWNER:-aryanshoh}"
GH_REPO="${GH_REPO:-sc-catalog-manager}"
VERSION="${VERSION:-1.5}"
BUILD="${BUILD:-6}"

APP_NAME="SubliminalClub Catalog Manager"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
UPDATES="$DIST/updates"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
GENERATE_APPCAST="$SPARKLE_BIN/generate_appcast"

if [ "$GH_OWNER" = "OWNER" ] || [ "$GH_REPO" = "REPO" ]; then
    echo "⚠ GH_OWNER/GH_REPO не заданы — ссылки в appcast будут с плейсхолдерами."
    echo "  Задайте их: GH_OWNER=you GH_REPO=catalog ./release.sh"
fi
[ -x "$GENERATE_APPCAST" ] || { echo "Не найден generate_appcast — сначала запустите swift build."; exit 1; }

# --- 1. собрать .app нужной версии ------------------------------------------
echo "▸ Сборка приложения (v$VERSION, build $BUILD)…"
VERSION="$VERSION" BUILD="$BUILD" GH_OWNER="$GH_OWNER" GH_REPO="$GH_REPO" "$ROOT/build_app.sh"

# --- 2. архив .app -----------------------------------------------------------
echo "▸ Архивация .app…"
mkdir -p "$UPDATES"
# Чистим папку от прошлых версий: у нас модель «в последнем релизе лежит appcast
# только на текущую версию» (URL старых zip указывали бы на другой релиз).
rm -f "$UPDATES"/*.zip "$UPDATES"/appcast.xml
ZIP="$UPDATES/CatalogManager-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

# --- 3. подпись + appcast ----------------------------------------------------
echo "▸ Подпись и генерация appcast…"
"$GENERATE_APPCAST" \
    --download-url-prefix "https://github.com/$GH_OWNER/$GH_REPO/releases/download/v$VERSION/" \
    "$UPDATES"

echo ""
echo "✅ Готово. Загрузите оба файла в GitHub Release с тегом v$VERSION:"
echo "   $ZIP"
echo "   $UPDATES/appcast.xml"
