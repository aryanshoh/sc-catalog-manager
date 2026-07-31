# SubliminalClub Catalog Manager — iOS

iOS-порт менеджера каталога, адаптированный под iPhone. **Всё бизнес-ядро
переиспользуется** из macOS-версии (`../Sources/CatalogManager/Core`) без
изменений — портирован только UI-слой и платформенные интеграции.

## Что адаптировано под iPhone

| macOS-версия                              | iOS-версия                                        |
|-------------------------------------------|---------------------------------------------------|
| Sidebar-навигация (сайт/разделы/тема)     | Нижний `TabView`: Каталог · Актуализация · Экспорт · Настройки |
| Master-detail (список + панель товара)    | `NavigationStack` с push: список → экран товара   |
| Поиск отдельным полем                     | Системный `.searchable`                           |
| Модальные `NSAlert` (синхронные)          | Асинхронный `DialogCoordinator` (`await confirm`) + `.alert` |
| `NSOpenPanel`                             | `.fileImporter` + security-scoped доступ          |
| `NSSavePanel`                             | `.fileExporter` (`CatalogTextDocument`)           |
| Пути к каталогам в settings.json          | Security-scoped **закладки** (песочница iOS)       |
| Выбор сайта / темы в sidebar              | Вкладка «Настройки»                               |
| Безрамочное окно, «светофоры», хром       | — (не нужно на iOS)                               |

Тема (Nocturne / светлая / розово-золотая) и её сохранение перенесены полностью.
Папка приложения видна в «Файлах» (`LSSupportsOpeningDocumentsInPlace`), так что
txt-каталоги можно открывать «на месте».

## Требования

- Xcode 16+ (проверено на Xcode 26), iOS 17+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) — генерирует `.xcodeproj`
  (`brew install xcodegen`)

## Сборка и запуск

```bash
cd ios
xcodegen generate           # создаёт CatalogManageriOS.xcodeproj из project.yml
open CatalogManageriOS.xcodeproj
```

Дальше — обычный Run в Xcode (⌘R) на симуляторе или устройстве.

### Сборка из терминала (симулятор)

```bash
cd ios
xcodegen generate
xcodebuild -project CatalogManageriOS.xcodeproj -target CatalogManager \
    -configuration Debug -sdk iphonesimulator -arch arm64 \
    CONFIGURATION_BUILD_DIR="$PWD/.build_ios/Products" build

xcrun simctl install booted "$PWD/.build_ios/Products/CatalogManager.app"
xcrun simctl launch booted com.subliminalclub.catalogmanager
```

`project.yml` — единственный источник правды о проекте; сам `.xcodeproj`
не коммитится (генерируется из него).
