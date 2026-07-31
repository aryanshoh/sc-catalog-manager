import Foundation
import SwiftSoup

// Скрапинг WooCommerce-витрины и страниц товаров — порт сетевой части
// catalog_core.py (create_session, fetch, call_with_reconnect,
// collect_product_links, fetch_product) на URLSession + SwiftSoup.

/// Кооперативный флаг отмены, разделяемый между UI и фоновой задачей.
/// Аналог threading.Event из Python-версии.
final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func set() { lock.lock(); value = true; lock.unlock() }
    func clear() { lock.lock(); value = false; lock.unlock() }
}

enum ScrapeError: LocalizedError {
    case runtime(String)
    case http(status: Int, url: String)

    var errorDescription: String? {
        switch self {
        case .runtime(let message):
            return message
        case .http(let status, let url):
            return "HTTP \(status) для \(url)"
        }
    }
}

/// Товар, найденный на странице-списке магазина: ссылка и (если удалось
/// вытащить из разметки списка) название — для «поверхностной» актуализации,
/// где сверка идёт по названию без захода в карточку товара.
struct ProductEntry: Sendable {
    let url: String
    let title: String?
}

// Sendable: после init нет изменяемого состояния (session неизменяем и
// потокобезопасен), поэтому объект безопасно шарить между задачами.
final class Scraper: @unchecked Sendable {
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = CoreConstants.requestTimeout
        config.timeoutIntervalForResource = CoreConstants.requestTimeout
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpAdditionalHeaders = [
            "User-Agent": CoreConstants.userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9",
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - HTTP

    // Соответствует "нет связи вообще" (обрыв Wi-Fi/интернета, DNS не
    // резолвится) — эти ошибки имеет смысл повторять неограниченно, в отличие
    // от HTTP-кодов, которые означают, что сайт ответил.
    private static func isNetworkError(_ error: URLError) -> Bool {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .dataNotAllowed, .internationalRoamingOff, .resourceUnavailable,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    private static let statusForcelist: Set<Int> = [408, 425, 429, 500, 502, 503, 504]

    /// Загружает страницу с авто-ретраем транзиентных статусов (как urllib3
    /// Retry) и особой обработкой 403 (как fetch() в Python).
    func fetch(_ urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw ScrapeError.runtime("Некорректный URL: \(urlString)")
        }

        var attempt = 0
        let maxAttempts = 5
        while true {
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse else {
                return decode(data)
            }
            let status = http.statusCode

            if Scraper.statusForcelist.contains(status), attempt < maxAttempts {
                attempt += 1
                let backoff = pow(2.0, Double(attempt - 1))  // 1, 2, 4, 8, 16 c
                try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                continue
            }
            if status == 403 {
                throw ScrapeError.runtime(
                    "Сайт вернул HTTP 403 для \(urlString). Возможно, сработала защита сайта. "
                    + "Попробуйте запустить актуализацию позже."
                )
            }
            if status >= 400 {
                throw ScrapeError.http(status: status, url: urlString)
            }
            return decode(data)
        }
    }

    private func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    /// Случайная пауза между запросами (джиттер) — чтобы интервал не выглядел
    /// «метрономом» и хуже детектировался как автоматизация.
    static func randomPacingDelay() -> Double {
        Double.random(in: CoreConstants.requestDelayMinSeconds...CoreConstants.requestDelayMaxSeconds)
    }

    /// Пейсинг-пауза со случайным разбросом, прерываемая флагом отмены.
    static func humanPacingSleep(cancel: CancelFlag) async throws {
        try await interruptibleSleep(randomPacingDelay(), cancel: cancel)
    }

    /// Ждёт `seconds`, дробя ожидание, чтобы можно было прервать по флагу отмены.
    static func interruptibleSleep(_ seconds: Double, cancel: CancelFlag) async throws {
        var waited = 0.0
        while waited < seconds {
            if cancel.isSet { throw CancelledError() }
            let chunk = min(1.0, seconds - waited)
            try await Task.sleep(nanoseconds: UInt64(chunk * 1_000_000_000))
            waited += chunk
        }
    }

    /// При обрыве сети не сдаётся, а ждёт с растущей паузой и пробует снова —
    /// неограниченно долго, пока сеть не восстановится или пользователь не
    /// нажмёт «Остановить». Порт call_with_reconnect.
    func callWithReconnect<T>(
        _ description: String,
        log: @Sendable (String) -> Void,
        cancel: CancelFlag,
        _ operation: () async throws -> T
    ) async throws -> T {
        var delay = 5.0
        let maxDelay = 60.0
        var attempt = 0
        while true {
            if cancel.isSet { throw CancelledError() }
            do {
                return try await operation()
            } catch let error as URLError where Scraper.isNetworkError(error) {
                attempt += 1
                log(
                    "Нет соединения с сетью (\(description)), попытка \(attempt): "
                    + "\(error.localizedDescription). Повторю через \(Int(delay)) с — "
                    + "актуализацию можно остановить кнопкой «Остановить»."
                )
                try await Scraper.interruptibleSleep(delay, cancel: cancel)
                delay = min(delay * 2, maxDelay)
            }
        }
    }

    // MARK: - URL-утилиты

    static func canonicalURL(_ url: String, base: String) -> String {
        let baseURL = URL(string: base)
        guard let absolute = URL(string: url, relativeTo: baseURL)?.absoluteURL,
              var comps = URLComponents(url: absolute, resolvingAgainstBaseURL: true) else {
            return url
        }
        comps.fragment = nil
        comps.query = nil
        var path = RegexPattern("/{2,}").replacingMatches(in: comps.path, with: "/")
        if !path.hasSuffix("/") { path += "/" }
        comps.path = path
        return comps.string ?? absolute.absoluteString
    }

    static func isProductURL(_ url: String, expectedHost: String) -> Bool {
        guard let comps = URLComponents(string: url) else { return false }
        return comps.host == expectedHost && comps.path.contains("/product/")
    }

    // MARK: - Сбор ссылок каталога

    private static let loopSelectors = [
        "li.product a.woocommerce-LoopProduct-link[href]",
        "ul.products li.product a[href*='/product/']",
        "a[href*='subliminalclub.com/product/']",
    ]
    private static let loopTitleSelectors =
        "h2.woocommerce-loop-product__title, .woocommerce-loop-product__title, h2, h3"

    /// Достаёт название товара из разметки списка: сперва внутри самой ссылки,
    /// затем — в ближайшем предке li.product. nil, если не нашлось.
    private static func loopTitle(for anchor: Element) throws -> String? {
        if let element = try anchor.select(loopTitleSelectors).first(),
           let text = try HTMLPlainText.textOrNil(element) {
            return text
        }
        var node: Element? = anchor.parent()
        var hops = 0
        while let current = node, hops < 6 {
            let classes = (try? current.attr("class")) ?? ""
            if current.tagName() == "li" || classes.contains("product") {
                if let element = try current.select(loopTitleSelectors).first(),
                   let text = try HTMLPlainText.textOrNil(element) {
                    return text
                }
            }
            node = current.parent()
            hops += 1
        }
        return nil
    }

    /// Разбирает одну страницу-список: пары (ссылка, название) в порядке обхода.
    /// Чистая функция без сети — удобно тестировать.
    static func extractEntries(from soup: Document, pageURL: String, expectedHost: String) throws -> [ProductEntry] {
        var entries: [ProductEntry] = []
        var seen = Set<String>()
        for selector in loopSelectors {
            for anchor in try soup.select(selector).array() {
                let href = try anchor.attr("href")
                if href.isEmpty { continue }
                let productURL = canonicalURL(href, base: pageURL)
                guard isProductURL(productURL, expectedHost: expectedHost), !seen.contains(productURL) else { continue }
                seen.insert(productURL)
                entries.append(ProductEntry(url: productURL, title: try loopTitle(for: anchor)))
            }
        }
        return entries
    }

    /// Обходит все страницы витрины и собирает товары (ссылка + название).
    func collectProductEntries(
        shopURL: String,
        log: @Sendable (String) -> Void,
        cancel: CancelFlag
    ) async throws -> [ProductEntry] {
        let expectedHost = URLComponents(string: shopURL)?.host ?? ""
        var pageURL = shopURL
        var visitedPages = Set<String>()
        var entries: [ProductEntry] = []
        var seenURLs = Set<String>()

        for pageNumber in 1...CoreConstants.maxCatalogPages {
            if cancel.isSet { throw CancelledError() }

            pageURL = Scraper.canonicalURL(pageURL, base: shopURL)
            if visitedPages.contains(pageURL) { break }
            visitedPages.insert(pageURL)

            log("Каталог: страница \(pageNumber) — \(pageURL)")
            let currentPage = pageURL
            let html = try await callWithReconnect(
                "страница каталога \(pageNumber)", log: log, cancel: cancel
            ) {
                try await self.fetch(currentPage)
            }
            let soup = try SwiftSoup.parse(html)

            var foundOnPage = 0
            for entry in try Scraper.extractEntries(from: soup, pageURL: currentPage, expectedHost: expectedHost)
                where !seenURLs.contains(entry.url) {
                seenURLs.insert(entry.url)
                entries.append(entry)
                foundOnPage += 1
            }
            log("Найдено новых товаров: \(foundOnPage); всего уникальных: \(entries.count)")

            var nextHref = try soup.select("a.next.page-numbers[href]").first()?.attr("href")
            if nextHref == nil || nextHref?.isEmpty == true {
                nextHref = try soup.select("link[rel='next'][href]").first()?.attr("href")
            }
            guard let next = nextHref, !next.isEmpty else { break }

            pageURL = URL(string: next, relativeTo: URL(string: currentPage))?.absoluteString ?? next
            try await Scraper.humanPacingSleep(cancel: cancel)

            if pageNumber == CoreConstants.maxCatalogPages {
                throw ScrapeError.runtime("Достигнут лимит MAX_CATALOG_PAGES=\(CoreConstants.maxCatalogPages).")
            }
        }

        if entries.isEmpty {
            throw ScrapeError.runtime("Не удалось найти ни одной ссылки товара в каталоге сайта.")
        }
        return entries
    }

    /// Только ссылки (для полной актуализации, где название берётся из карточки).
    func collectProductLinks(
        shopURL: String,
        log: @Sendable (String) -> Void,
        cancel: CancelFlag
    ) async throws -> [String] {
        try await collectProductEntries(shopURL: shopURL, log: log, cancel: cancel).map { $0.url }
    }

    // MARK: - Разбор страницы товара

    private static func dedupePreserveOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let key = value.lowercased()
            if !seen.contains(key) {
                seen.insert(key)
                result.append(value)
            }
        }
        return result
    }

    private func extractMetaLine(_ soup: Document) throws -> (categories: [String], tags: [String]) {
        var categories: [String] = []
        var tags: [String] = []

        if let postedIn = try soup.select(".product_meta .posted_in").first() {
            let raw = try postedIn.select("a").array().compactMap { try HTMLPlainText.textOrNil($0) }
            categories = Scraper.dedupePreserveOrder(raw)
        }
        if let taggedAs = try soup.select(".product_meta .tagged_as").first() {
            let raw = try taggedAs.select("a").array().compactMap { try HTMLPlainText.textOrNil($0) }
            tags = Scraper.dedupePreserveOrder(raw)
        }
        return (categories, tags)
    }

    // MARK: - Даты публикации и изменения

    /// Дата публикации товара из разметки страницы в формате dd.MM.yyyy, либо nil.
    func extractPublishDate(_ soup: Document) throws -> String? {
        try extractDate(soup, metaProperty: "article:published_time", jsonKey: "datePublished")
    }

    /// Дата последнего изменения товара на сайте в формате dd.MM.yyyy, либо nil.
    func extractModifiedDate(_ soup: Document) throws -> String? {
        try extractDate(soup, metaProperty: "article:modified_time", jsonKey: "dateModified")
    }

    /// Общий разбор даты. Источники по приоритету: мета-тег `metaProperty` и
    /// поле `jsonKey` из JSON-LD (узел страницы @type WebPage/ItemPage). Даты
    /// отзывов (вложены в Product.review[]) сюда не попадают — берётся только
    /// узел самой страницы.
    private func extractDate(_ soup: Document, metaProperty: String, jsonKey: String) throws -> String? {
        var iso = try soup.select("meta[property='\(metaProperty)'][content]")
            .first()?.attr("content")
        if iso?.isEmpty ?? true {
            iso = Scraper.dateFromJSONLD(soup, key: jsonKey)
        }
        guard let raw = iso, !raw.isEmpty else { return nil }
        return CatalogText.formatPublishDate(fromISO: raw)
    }

    private static func dateFromJSONLD(_ soup: Document, key: String) -> String? {
        guard let scripts = try? soup.select("script[type='application/ld+json']").array() else {
            return nil
        }
        for script in scripts {
            guard let data = script.data().data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) else { continue }
            if let date = pageDate(obj, key: key) { return date }
        }
        return nil
    }

    /// Рекурсивно ищет поле `key` у узла страницы (@type содержит WebPage или
    /// ItemPage). Спуск идёт только по @graph и вложенным массивам узлов, а не
    /// внутрь произвольных полей, поэтому даты отзывов (Review) не подхватываются.
    private static func pageDate(_ any: Any, key: String) -> String? {
        if let dict = any as? [String: Any] {
            if let graph = dict["@graph"], let found = pageDate(graph, key: key) {
                return found
            }
            let types = typeList(dict["@type"])
            if types.contains("WebPage") || types.contains("ItemPage"),
               let value = dict[key] as? String, !value.isEmpty {
                return value
            }
        } else if let arr = any as? [Any] {
            for item in arr {
                if let found = pageDate(item, key: key) { return found }
            }
        }
        return nil
    }

    private static func typeList(_ value: Any?) -> [String] {
        if let s = value as? String { return [s] }
        if let a = value as? [Any] { return a.compactMap { $0 as? String } }
        return []
    }

    /// Загружает страницу товара и возвращает структурированный Product.
    func fetchProduct(_ productURL: String, titleSuffixPattern: String) async throws -> Product {
        let html = try await fetch(productURL)
        let soup = try SwiftSoup.parse(html)

        var title = try HTMLPlainText.textOrNil(try soup.select("h1.product_title, h1.entry-title").first())
        if title == nil {
            let ogTitle = (try soup.select("meta[property='og:title'][content]").first()?.attr("content")) ?? ""
            var candidate = ogTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty { candidate = "Без названия" }
            candidate = RegexPattern("\\s*[-|]\\s*(?:\(titleSuffixPattern))\\s*$", options: [.caseInsensitive])
                .replacingMatches(in: candidate, with: "")
            title = candidate
        }

        var sections = OrderedStringMap()

        if let shortDesc = try soup.select(
            ".summary.entry-summary .woocommerce-product-details__short-description, "
            + ".woocommerce-product-details__short-description"
        ).first() {
            let text = try HTMLPlainText.plainText(from: shortDesc)
            if !text.isEmpty { sections["Краткое описание"] = text }
        }

        let (categories, tags) = try extractMetaLine(soup)
        var metaLines: [String] = []
        if !categories.isEmpty { metaLines.append("Categories: " + categories.joined(separator: ", ")) }
        if !tags.isEmpty { metaLines.append("Tags: " + tags.joined(separator: ", ")) }
        if !metaLines.isEmpty { sections["Категории и теги"] = metaLines.joined(separator: "\n") }

        if let publishDate = try extractPublishDate(soup) {
            sections[CoreConstants.publishDateSection] = publishDate
        }
        if let modifiedDate = try extractModifiedDate(soup) {
            sections[CoreConstants.modifiedDateSection] = modifiedDate
        }

        if let description = try soup.select(
            "#tab-description, "
            + ".woocommerce-Tabs-panel--description, "
            + ".woocommerce-tabs .panel.entry-content"
        ).first() {
            let text = try HTMLPlainText.plainText(from: description)
            if !text.isEmpty { sections["Полное описание"] = text }
        } else if let summary = try soup.select(".summary.entry-summary").first() {
            try summary.select(
                "form, button, input, select, .quantity, .cart, .product_meta, "
                + ".price, .woocommerce-product-rating, h1"
            ).remove()
            let text = try HTMLPlainText.plainText(from: summary)
            if !text.isEmpty { sections["Полное описание"] = text }
        }

        return Product(title: title ?? "Без названия", sections: sections, url: productURL)
    }
}
