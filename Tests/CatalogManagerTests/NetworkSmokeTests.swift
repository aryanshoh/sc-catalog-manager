import XCTest
import SwiftSoup
@testable import CatalogManager

// Сетевой smoke-тест против настоящих сайтов. По умолчанию пропускается —
// запускать с RUN_NETWORK_TESTS=1. Не гоняет полную актуализацию: берёт одну
// страницу витрины, собирает ссылки и разбирает один товар end-to-end.
final class NetworkSmokeTests: XCTestCase {

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RUN_NETWORK_TESTS"] == "1",
            "Сетевой тест пропущен — запустите с RUN_NETWORK_TESTS=1"
        )
    }

    private func runPipeline(for site: Site) async throws {
        print("\n=== \(site.shortLabel) — \(site.shopURL) ===")
        let scraper = Scraper()

        // 1. Первая страница магазина.
        let html = try await scraper.fetch(site.shopURL)
        let soup = try SwiftSoup.parse(html)
        let host = URLComponents(string: site.shopURL)?.host ?? ""

        var links: [String] = []
        for selector in [
            "li.product a.woocommerce-LoopProduct-link[href]",
            "ul.products li.product a[href*='/product/']",
            "a[href*='subliminalclub.com/product/']",
        ] {
            for anchor in try soup.select(selector).array() {
                let url = Scraper.canonicalURL(try anchor.attr("href"), base: site.shopURL)
                if Scraper.isProductURL(url, expectedHost: host), !links.contains(url) {
                    links.append(url)
                }
            }
        }
        print("Ссылок товаров на первой странице: \(links.count)")
        XCTAssertFalse(links.isEmpty, "На витрине \(site.shortLabel) должна быть хотя бы одна ссылка товара")
        guard let first = links.first else { return }

        // 2. Разбор одного товара end-to-end.
        let product = try await scraper.fetchProduct(first, titleSuffixPattern: site.titleSuffixPattern)
        print("URL:        \(first)")
        print("Название:   \(product.title)")
        print("Категории:  \(product.categories())")
        print("Теги:       \(CatalogText.parseTags(product.sections[CoreConstants.categoriesSection] ?? ""))")
        for name in CoreConstants.sectionOrder {
            if let value = product.sections[name], !value.isEmpty {
                let preview = value.replacingOccurrences(of: "\n", with: " ⏎ ").prefix(200)
                print("[\(name)] \(preview)")
            }
        }

        XCTAssertFalse(product.title.isEmpty)
        XCTAssertNotEqual(product.title, "Untitled", "Не удалось извлечь название товара")
    }

    func testSurfaceListingTitles() async throws {
        let site = Sites.site(forKey: "subliminalclub")
        let scraper = Scraper()
        let html = try await scraper.fetch(site.shopURL)
        let soup = try SwiftSoup.parse(html)
        let host = URLComponents(string: site.shopURL)?.host ?? ""
        let entries = try Scraper.extractEntries(from: soup, pageURL: site.shopURL, expectedHost: host)
        let withTitle = entries.filter { $0.title != nil }
        print("\nПоверхностный разбор (первая страница): товаров \(entries.count), с названием \(withTitle.count)")
        for e in entries.prefix(5) { print("  • \(e.title ?? "—")  ←  \(e.url)") }
        XCTAssertFalse(entries.isEmpty)
        // Названия должны читаться из списка у большинства (иначе экономии нет).
        XCTAssertGreaterThan(withTitle.count, entries.count / 2)
    }

    func testSubliminalClubPipeline() async throws {
        try await runPipeline(for: Sites.site(forKey: "subliminalclub"))
    }

    func testQuintessencePipeline() async throws {
        try await runPipeline(for: Sites.site(forKey: "quintessence"))
    }
}
