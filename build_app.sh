#!/bin/bash
# Собирает распространяемое macOS-приложение из Swift-пакета:
#   1) релизная сборка бинарника (swift build -c release)
#   2) иконка-мозг (build_assets/AppIcon.icns; генерируется при отсутствии)
#   3) бандл .app (Info.plist + иконка + исполняемый файл), ad-hoc подпись
#   4) оформленный .dmg (кремовый фон + стрелка + позиции иконок)
#
# Использование:  ./build_app.sh
# Результат:      dist/<APP_NAME>.app  и  dist/<APP_NAME>.dmg
set -euo pipefail

# --- параметры ---------------------------------------------------------------
APP_NAME="SubliminalClub Catalog Manager"
BUNDLE_ID="com.subliminalclub.catalog-manager"
EXECUTABLE="CatalogManager"
# Версию и номер сборки можно переопределить из окружения при релизе:
#   VERSION=1.2 BUILD=3 ./build_app.sh
# Sparkle сравнивает обновления по BUILD (CFBundleVersion) — он должен расти.
VERSION="${VERSION:-1.5}"
BUILD="${BUILD:-6}"
MIN_MACOS="14.0"

# --- авто-обновление (Sparkle) ----------------------------------------------
# GitHub для хостинга обновлений (appcast + zip лежат в Releases).
GH_OWNER="${GH_OWNER:-aryanshoh}"
GH_REPO="${GH_REPO:-sc-catalog-manager}"
# «latest/download» всегда отдаёт ассет из последнего релиза — стабильный URL.
FEED_URL="https://github.com/$GH_OWNER/$GH_REPO/releases/latest/download/appcast.xml"
# Публичный ключ EdDSA (приватный — в Keychain, им подписывается каждый релиз).
SU_PUBLIC_ED_KEY="ariT4d4HevsSTE/KIsvC0FAxl0Zvxlk8NxqnLgZPWBo="

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
ASSETS="$ROOT/build_assets"
ICON="$ASSETS/AppIcon.icns"
DMG_BG="$ASSETS/dmg_background.png"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
# Python из .venv Qt-версии (там есть PySide6 для генерации картинок).
VENV_PY="$ROOT/../qt_catalog_manager/.venv/bin/python"

# --- 1. релизная сборка ------------------------------------------------------
echo "▸ Сборка релиза…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/$EXECUTABLE"
[ -f "$BIN" ] || { echo "Не найден бинарник: $BIN"; exit 1; }

# --- 2. ассеты (иконка + фон dmg) --------------------------------------------
if [ ! -f "$ICON" ] && [ -x "$VENV_PY" ]; then
    echo "▸ Генерация иконки…"
    QT_QPA_PLATFORM=offscreen "$VENV_PY" "$ASSETS/make_icon.py"
fi
if [ ! -f "$DMG_BG" ] && [ -x "$VENV_PY" ]; then
    echo "▸ Генерация фона dmg…"
    QT_QPA_PLATFORM=offscreen "$VENV_PY" "$ASSETS/make_dmg_bg.py"
fi

# --- 3. каркас бандла --------------------------------------------------------
echo "▸ Сборка бандла .app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
chmod +x "$APP/Contents/MacOS/$EXECUTABLE"

# Встраиваем Sparkle.framework (лежит рядом с бинарником после сборки) в бандл
# и добавляем rpath, чтобы исполняемый файл нашёл его как @executable_path/../Frameworks.
SPARKLE_FW="$(dirname "$BIN")/Sparkle.framework"
if [ -d "$SPARKLE_FW" ]; then
    cp -R "$SPARKLE_FW" "$APP/Contents/Frameworks/"
    install_name_tool -add_rpath "@executable_path/../Frameworks" \
        "$APP/Contents/MacOS/$EXECUTABLE" 2>/dev/null || true
else
    echo "  ⚠ Sparkle.framework не найден рядом с бинарником — авто-обновление не будет работать"
fi

if [ -f "$ICON" ]; then
    cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
    ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
else
    echo "  (иконка не найдена — бандл без иконки)"; ICON_KEY=""
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    $ICON_KEY
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key><string>SubliminalClub Catalog Manager</string>
    <key>SUFeedURL</key><string>$FEED_URL</string>
    <key>SUPublicEDKey</key><string>$SU_PUBLIC_ED_KEY</string>
    <key>SUEnableAutomaticChecks</key><false/>
</dict>
</plist>
PLIST

echo "▸ Подпись (ad-hoc)…"
# Подписываем изнутри наружу: сперва встроенный фреймворк (со всеми вложенными
# XPC-хелперами Sparkle), затем весь бандл.
if [ -d "$APP/Contents/Frameworks/Sparkle.framework" ]; then
    codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework"
fi
codesign --force --deep --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP" && echo "  подпись ок"

# --- 4. оформленный .dmg -----------------------------------------------------
echo "▸ Сборка .dmg…"
DMG="$DIST/$APP_NAME.dmg"
STAGING="$DIST/dmg_staging"
RW="$DIST/rw.dmg"
rm -f "$DMG" "$RW"; rm -rf "$STAGING"
mkdir -p "$STAGING/.background"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
[ -f "$DMG_BG" ] && cp "$DMG_BG" "$STAGING/.background/dmg_background.png"

# Отмонтируем все «висящие» тома от прошлых запусков (включая варианты с
# суффиксами « 1», « 2»… которые macOS создаёт, если том с этим именем занят).
# Иначе они копятся и засоряют LaunchServices (приложение перестаёт
# показываться в Launchpad/«Apps»).
for V in "/Volumes/$APP_NAME" "/Volumes/$APP_NAME "[0-9]*; do
    [ -d "$V" ] && { hdiutil detach "$V" -force >/dev/null 2>&1 || true; }
done

hdiutil create -srcfolder "$STAGING" -volname "$APP_NAME" -fs HFS+ \
    -format UDRW -ov "$RW" >/dev/null

ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW")"
DEV="$(echo "$ATTACH_OUT" | egrep '^/dev/' | head -1 | awk '{print $1}')"
MOUNT_DIR="$(echo "$ATTACH_OUT" | sed -n 's/.*\(\/Volumes\/.*\)$/\1/p' | head -1)"
sleep 1

# Стилизация окна через Finder (best-effort: требует разрешения на
# автоматизацию Finder; при отказе dmg соберётся без оформления).
if [ -f "$DMG_BG" ]; then
osascript <<OSA 2>/dev/null && echo "  окно оформлено" || echo "  (оформление окна пропущено — dmg соберётся без него)"
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 760, 543}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set background picture of opts to file ".background:dmg_background.png"
    set position of item "$APP_NAME.app" of container window to {150, 235}
    set position of item "Applications" of container window to {410, 235}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
fi

sync
# Надёжное отмонтирование по устройству, с ретраями (иначе convert падает
# с «Resource temporarily unavailable», пока том ещё занят).
for attempt in 1 2 3 4 5; do
    if hdiutil detach "$DEV" >/dev/null 2>&1 || hdiutil detach "$DEV" -force >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
sleep 1
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null
rm -f "$RW"; rm -rf "$STAGING"

echo ""
echo "✅ Готово:"
echo "   $APP"
echo "   $DMG"
