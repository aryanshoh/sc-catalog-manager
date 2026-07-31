import Foundation

// Порт catalog_core.py — фреймворк-независимая модель каталога и константы.
// Никакого UI здесь нет: этот слой одинаково пригоден для SwiftUI-версии и
// для любого другого фронтенда.

enum CoreConstants {
    static let separatorLine = String(repeating: "=", count: 80)

    /// Название секции с категориями и тегами товара.
    static let categoriesSection = "Categories & tags"
    /// Название секции с датой публикации товара на сайте.
    static let publishDateSection = "Publication date"
    /// Название секции с датой последнего изменения товара на сайте.
    static let modifiedDateSection = "Modification date"
    /// Название секции с кратким описанием товара.
    static let shortDescriptionSection = "Short description"
    /// Название секции с полным описанием товара.
    static let fullDescriptionSection = "Full description"

    // Порядок секций товара в txt-каталоге: категории, даты публикации и
    // изменения, затем краткое и полное описание.
    static let sectionOrder = [
        categoriesSection,
        publishDateSection,
        modifiedDateSection,
        shortDescriptionSection,
        fullDescriptionSection,
    ]

    static let requestTimeout: TimeInterval = 45
    // Пейсинг между запросами задаётся не фиксированной секундой, а случайным
    // интервалом в этом диапазоне — ровный «метрономный» шаг легко палится как
    // бот, поэтому добавляем джиттер.
    static let requestDelayMinSeconds: TimeInterval = 0.8
    static let requestDelayMaxSeconds: TimeInterval = 2.5
    static let maxCatalogPages = 150

    static let userAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) "
        + "Chrome/126.0 Safari/537.36"
}

/// Скрапинг остановлен пользователем.
struct CancelledError: Error {}

// MARK: - Сайт

struct Site: Identifiable, Hashable {
    let key: String
    let shortLabel: String
    let label: String
    let shopURL: String
    /// Паттерн для отбрасывания названия сайта из og:title (запасной вариант,
    /// если на странице нет <h1>).
    let titleSuffixPattern: String
    /// Заголовок первой строки txt-каталога для новых каталогов.
    let catalogHeader: String

    var id: String { key }
}

enum Sites {
    static let all: [Site] = [
        Site(
            key: "subliminalclub",
            shortLabel: "SubliminalClub",
            label: "SubliminalClub — subliminalclub.com/shop",
            shopURL: "https://www.subliminalclub.com/shop/",
            titleSuffixPattern: "SubliminalClub",
            catalogHeader: "SubliminalClub — product page contents"
        ),
        Site(
            key: "quintessence",
            shortLabel: "Quintessence",
            label: "Quintessence — q.subliminalclub.com/shop",
            shopURL: "https://q.subliminalclub.com/shop/",
            titleSuffixPattern: "Quintessence|SubliminalClub",
            catalogHeader: "Quintessence (q.subliminalclub.com) — product page contents"
        ),
    ]

    static let `default` = all[0]

    static func site(forKey key: String) -> Site {
        all.first { $0.key == key } ?? `default`
    }
}

// MARK: - Товар

/// Модель товара. Идентичность по ссылке (class-семантика оригинального
/// dataclass), чтобы «сироты» можно было отсеивать по тождеству объекта, как
/// это делает Python-версия через id(p).
///
/// @unchecked Sendable: объект передаётся в фоновую задачу актуализации, но
/// владелец в каждый момент времени один (главный поток не мутирует товары,
/// пока идёт сверка), поэтому гонок нет.
final class Product: Identifiable, Hashable, @unchecked Sendable {
    static func == (lhs: Product, rhs: Product) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    var id: ObjectIdentifier { ObjectIdentifier(self) }

    var title: String
    /// Секции в порядке появления, например:
    /// ["Краткое описание": "...", "Категории и теги": "Categories: A, B", ...]
    var sections: OrderedStringMap
    var url: String?

    init(title: String, sections: OrderedStringMap = OrderedStringMap(), url: String? = nil) {
        self.title = title
        self.sections = sections
        self.url = url
    }

    func categories() -> [String] {
        CatalogText.parseCategories(sections[CoreConstants.categoriesSection] ?? "")
    }

    /// Нормализованный «отпечаток» содержимого для сравнения товара с сайтом.
    func signature() -> String {
        let short = sections[CoreConstants.shortDescriptionSection] ?? ""
        let full = sections[CoreConstants.fullDescriptionSection] ?? ""
        let text = "\(title)\n\(short)\n\(full)"
        let normalizedText = RegexPattern("\\s+")
            .replacingMatches(in: text, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let categories = categories().map { $0.lowercased() }.sorted()
        let tags = CatalogText.parseTags(sections[CoreConstants.categoriesSection] ?? "")
            .map { $0.lowercased() }.sorted()
        return "\(normalizedText)|CATS:\(categories.joined(separator: ","))|TAGS:\(tags.joined(separator: ","))"
    }

    func toBlock() -> String {
        var lines: [String] = [title]

        func appendSection(_ name: String) {
            guard let content = sections[name], !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            lines.append("")
            lines.append(name)
            lines.append("")
            lines.append(content.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        for name in CoreConstants.sectionOrder {
            appendSection(name)
        }
        // Секции вне стандартного порядка сохраняем как есть, чтобы не терять
        // данные из старых файлов.
        for name in sections.keys where !CoreConstants.sectionOrder.contains(name) {
            appendSection(name)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Состояние каталога

/// Независимое состояние локального каталога для одного сайта.
struct CatalogState {
    let siteKey: String
    var path: URL?
    var header: String = ""
    var products: [Product] = []
    var dirty: Bool = false
    /// Отпечаток (SHA-256) файла на момент последней загрузки или сохранения.
    /// Позволяет заметить, что файл в общей/облачной папке успел изменить кто-то
    /// с другого устройства, прежде чем затирать его своей версией. `nil` — файл
    /// ещё не связан с состоянием (новый каталог) либо платформа не отслеживает
    /// конфликты (macOS).
    var loadedFileHash: String? = nil
}

// MARK: - Результат актуализации

struct ActualizationResult {
    var catalog: [Product]
    var added: [String] = []
    var updated: [String] = []
    var unchanged: [String] = []
    var orphans: [Product] = []
    var failed: [(url: String, error: String)] = []
}
