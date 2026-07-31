# Как выпускать обновления

Инструкция для человека и для ИИ-ассистента. macOS-приложение обновляется само
через **Sparkle**; файлы обновлений лежат в **GitHub Releases** репозитория
`aryanshoh/sc-catalog-manager`. Приложение подписано **ad-hoc** (без Apple
Developer ID) — авто-обновления при этом работают, но первая установка требует
«правый клик → Открыть».

---

## Быстрый путь (2 команды)

Допустим, выпускаем версию **1.3** (следующий номер сборки — **4**):

```bash
VERSION=1.3 BUILD=4 ./release.sh
```

```bash
gh release create v1.3 \
  "dist/updates/CatalogManager-1.3.zip" \
  "dist/updates/appcast.xml" \
  "dist/SubliminalClub Catalog Manager.dmg" \
  --title "v1.3" \
  --notes "Что нового в этой версии"
```

Готово. У всех, у кого установлено приложение, меню → «Проверить обновления…»
найдёт новую версию, скачает, проверит подпись и поставит с перезапуском.

---

## Правила версий (важно!)

- **VERSION** — видимый номер (`1.3`), пишется в `CFBundleShortVersionString`.
- **BUILD** — целое число (`4`), пишется в `CFBundleVersion`. **Именно по нему
  Sparkle понимает, что вышло обновление.** BUILD **обязан строго расти** с
  каждым релизом. Никогда не повторяйте и не уменьшайте его.
- **Тег релиза = `v<VERSION>`** (например `v1.3`) и должен совпадать с VERSION:
  `release.sh` зашивает в appcast ссылку на zip внутри релиза `v<VERSION>`, так
  что тег обязан быть ровно таким.
- Последняя выпущенная версия: **v1.4 / build 5** (значения по умолчанию в
  `build_app.sh` и `release.sh`). Следующая — минимум **build 6**.

Узнать, что сейчас в фиде:

```bash
curl -sL "https://github.com/aryanshoh/sc-catalog-manager/releases/latest/download/appcast.xml" | grep -E "shortVersionString|sparkle:version"
```

---

## Что делает `release.sh`

1. Собирает `.app` нужной версии (через `build_app.sh`): встраивает и подписывает
   `Sparkle.framework`, прописывает в Info.plist `SUFeedURL` и публичный ключ.
2. Чистит `dist/updates/` и кладёт туда `CatalogManager-<VERSION>.zip`.
3. Утилитой Sparkle `generate_appcast` подписывает архив приватным ключом
   (берётся из Keychain) и генерирует `dist/updates/appcast.xml`.

Файлы для загрузки в релиз — в `dist/updates/`. `.dmg` (для новых пользователей)
лежит в `dist/`.

---

## Проверка после релиза

```bash
# фид отдаёт новую версию?
curl -sL "https://github.com/aryanshoh/sc-catalog-manager/releases/latest/download/appcast.xml" | grep shortVersionString
# zip из appcast скачивается? (ждём HTTP 200)
curl -sIL "$(curl -sL https://github.com/aryanshoh/sc-catalog-manager/releases/latest/download/appcast.xml | grep -oE 'url="[^"]*\.zip"' | sed 's/url="//;s/"//')" | grep -i "^HTTP"
```

Финальная проверка — в приложении: меню → «Проверить обновления…».

---

## Подводные камни

- **Репозиторий должен быть публичным** — Sparkle качает обновления без токена.
- **Приватный ключ EdDSA — в Keychain** (это он подписывает релизы). Без него
  выпускать обновления нельзя. Бэкап (сделать один раз, хранить надёжно):
  ```bash
  .build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle_private_key_backup.txt
  ```
  Восстановить на новой машине: `generate_keys -f sparkle_private_key_backup.txt`.
- **Сборка только arm64** (Apple Silicon). Intel-Маки обновления не получают.
- **Первая установка** новым людям — через `.dmg`, «правый клик → Открыть»
  (ad-hoc подпись). Дальше они обновляются автоматически.
- Публичный ключ в приложении и приватный в Keychain — **пара**. Если
  перегенерировать ключи, старые установки перестанут принимать обновления.

---

## Для ИИ-ассистента

Контекст и точная последовательность (репозиторий уже настроен, `gh`
аутентифицирован как `aryanshoh`):

1. **Определи следующий BUILD.** Возьми текущий из фида и прибавь 1:
   ```bash
   curl -sL "https://github.com/aryanshoh/sc-catalog-manager/releases/latest/download/appcast.xml" | grep -oE '<sparkle:version>[0-9]+' | grep -oE '[0-9]+'
   ```
   Новый BUILD = это + 1. VERSION согласуй с пользователем (semver-номер).
2. **Закоммить изменения кода** (если релиз содержит правки), обычным порядком.
3. **Собери и подпиши:** `VERSION=<v> BUILD=<b> ./release.sh`. Скрипт сам чистит
   `dist/updates/`. Приватный ключ Sparkle берёт из Keychain автоматически.
4. **Создай релиз:**
   ```bash
   gh release create v<VERSION> \
     "dist/updates/CatalogManager-<VERSION>.zip" \
     "dist/updates/appcast.xml" \
     "dist/SubliminalClub Catalog Manager.dmg" \
     --title "v<VERSION>" --notes "<changelog>"
   ```
   (zip и appcast.xml — обязательны; .dmg — для первой установки новых людей.)
5. **Запушь коммит:** `git push origin main`.
6. **Проверь фид** (раздел «Проверка после релиза»): `shortVersionString` должен
   стать новым, zip — отдавать HTTP 200.
7. **Не трогай** публичный ключ (`SUPublicEDKey` в `build_app.sh`) и не
   перегенерируй ключи — иначе сломаются обновления у существующих установок.

Дополнительный контекст — в памяти проекта: `macos-auto-update-sparkle`.
