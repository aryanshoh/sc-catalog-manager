# SubliminalClub Catalog Manager — Swift-версия

Нативное macOS-приложение (SwiftUI), переписанное с Python/PySide6-версии
(`../qt_catalog_manager`). Бизнес-логика, формат txt-каталога, скрапинг
WooCommerce и механизм актуализации перенесены один-в-один; интерфейс —
нативный (тёмная тема Nocturne, безрамочное окно, sidebar-навигация).

## Требования

- macOS 14 (Sonoma) или новее
- Xcode 15+ или Command Line Tools со Swift 5.9+
- Доступ в интернет при первой сборке (тянется зависимость **SwiftSoup**)

## ⚠️ Один шаг вручную перед первой сборкой

Если `swift build` печатает `You have not agreed to the Xcode license
agreements`, нужно один раз принять лицензию Xcode. Это требует прав
администратора (ваш пароль), поэтому выполните команду сами:

```bash
sudo xcodebuild -license accept
```

## Сборка и запуск

```bash
cd "swift_catalog_manager"
swift run
```

Первый запуск скачает и соберёт SwiftSoup — это займёт минуту. Дальше окно
приложения откроется сразу.

Сборка релизной версии:

```bash
swift build -c release
```

Готовый бинарник появится в `.build/release/CatalogManager`. Это «голый»
исполняемый файл; чтобы получить полноценный `.app`-бандл с иконкой в Dock,
его нужно завернуть в бандл (или собрать проект в Xcode) — по аналогии с
`build_app.sh` из Python-версии.

## Сборка приложения для конечного пользователя

Чтобы получить обычное macOS-приложение (двойной клик по иконке, без терминала):

```bash
./build_app.sh
```

Скрипт собирает релиз, заворачивает бинарник в бандл `.app` (с `Info.plist` и
иконкой-мозгом), ad-hoc подписывает и упаковывает в оформленный `.dmg`
(кремовый фон в стиле светлой темы, стрелка и ярлык на `/Applications`).
Результат — в папке `dist/`:

- `dist/SubliminalClub Catalog Manager.app` — само приложение
- `dist/SubliminalClub Catalog Manager.dmg` — установщик (перетащить в Applications)

Ассеты (`build_assets/AppIcon.icns`, `build_assets/dmg_background.png`) уже
сгенерированы; при их отсутствии скрипт создаёт их заново через PySide6 из
`.venv` Qt-версии (`make_icon.py` / `make_dmg_bg.py`).

> При первом запуске скрипта macOS может спросить разрешение «Terminal хочет
> управлять Finder» — оно нужно для оформления окна `.dmg` (фон и позиции
> иконок). Если отказать, установщик всё равно соберётся, но без оформления.

Бандл самодостаточный: SwiftSoup слинкован статически, Swift-рантайм берётся из
самой macOS, внешних зависимостей нет.

### Первый запуск на чужом Маке (важно)

Приложение подписано **ad-hoc** (без платного сертификата Apple), поэтому при
первом открытии на другом компьютере Gatekeeper покажет предупреждение
«неустановленный разработчик». Это нормально; открыть можно одним из способов:

- **правый клик по иконке → «Открыть»** → в диалоге ещё раз «Открыть» (нужно
  один раз, дальше запускается обычным двойным кликом), либо
- снять карантин в терминале:
  ```bash
  xattr -dr com.apple.quarantine "/Applications/SubliminalClub Catalog Manager.app"
  ```

### Чистое распространение без предупреждений (платно)

Чтобы `.dmg` открывался двойным кликом у любого пользователя без предупреждений,
нужен **Apple Developer Program** ($99/год) и подпись сертификатом
*Developer ID Application* + нотаризация:

```bash
codesign --force --options runtime --sign "Developer ID Application: ВАШЕ ИМЯ (TEAMID)" \
    "dist/SubliminalClub Catalog Manager.app"
xcrun notarytool submit "dist/SubliminalClub Catalog Manager.dmg" \
    --apple-id ВАШ_APPLE_ID --team-id TEAMID --password APP_SPECIFIC_PASSWORD --wait
xcrun stapler staple "dist/SubliminalClub Catalog Manager.dmg"
```

(Сертификат *Apple Development*, который стоит в системе сейчас, для этого не
подходит — он только для запуска при разработке.)

## Тесты

```bash
swift test
```

23 юнит-теста на чистую логику ядра (без сети): нормализация названий,
разбор категорий/тегов, round-trip парсинг↔сериализация каталога, «отпечаток»
товара (`signature`), упорядоченный словарь секций, HTML→плоский текст
(списки, таблицы, пунктуация, пропуск скрытого текста) и URL-канонизация.

## Структура

```
Sources/CatalogManager/
  Core/                     — фреймворк-независимая логика (порт catalog_core.py)
    Models.swift            — Site, Product, CatalogState, ActualizationResult
    OrderedStringMap.swift  — упорядоченный словарь секций товара
    RegexHelpers.swift      — обёртка над NSRegularExpression (аналог re)
    CatalogText.swift       — парсинг/сериализация txt-каталога
    HTMLPlainText.swift     — HTML → плоский текст (SwiftSoup)
    Scraper.swift           — URLSession + SwiftSoup: сбор ссылок, разбор товара
    Actualizer.swift        — сверка каталога с сайтом (actualize_catalog)
    AppSettings.swift       — settings.json (совместим с Python-версией)
  UI/                       — SwiftUI-слой (порт catalog_app_qt.py)
    CatalogManagerApp.swift — @main, окно, делегат закрытия
    AppState.swift          — состояние и управляющий поток (порт MainWindow)
    ContentView.swift       — тулбар + sidebar + раздел + статус-бар
    SidebarView / MenuPageView / ActualizePageView / ExportPageView
    OrphanSheetView.swift   — модальный лист «сироты»
    Theme.swift             — токены Nocturne
    Components.swift        — кнопки, чипы, flow-раскладка
    Dialogs.swift           — NSAlert / NSOpenPanel / NSSavePanel

## Соответствие Python-версии

| Python / Qt                         | Swift                                   |
|-------------------------------------|-----------------------------------------|
| `requests` + `BeautifulSoup`        | `URLSession` (async) + `SwiftSoup`      |
| `threading` + `queue` + polling     | `async/await` + `@MainActor` + `Task`   |
| `threading.Event`                   | `CancelFlag`                            |
| PySide6 (frameless, «светофоры»)    | нативное окно `.hiddenTitleBar`         |
| `icons.py` (SVG Phosphor)           | SF Symbols                              |
| `app_settings.py`                   | `AppSettings.swift` (тот же JSON)       |

Настройки хранятся там же, где и у Python-версии:
`~/Library/Application Support/SubliminalClub Catalog Manager/settings.json`,
поэтому последние открытые каталоги подхватятся автоматически.
```
