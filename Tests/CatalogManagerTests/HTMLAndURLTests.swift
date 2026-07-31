import XCTest
import SwiftSoup
@testable import CatalogManager

final class PublishDateExtractionTests: XCTestCase {

    // JSON-LD со структурой, как на реальной странице: узел страницы с
    // datePublished + вложенный отзыв со своей датой (не должен подхватиться).
    func testExtractsPageDateFromJSONLDAndIgnoresReviewDate() throws {
        let html = """
        <html><head>
        <script type="application/ld+json">
        {"@context":"https://schema.org","@graph":[
          {"@type":["WebPage","ItemPage"],"datePublished":"2022-07-23T02:34:02+00:00","dateModified":"2026-05-24T19:03:54+00:00"},
          {"@type":"Product","name":"X","review":[{"@type":"Review","datePublished":"2025-06-10T09:14:35-04:00"}]}
        ]}
        </script>
        </head><body></body></html>
        """
        let soup = try SwiftSoup.parse(html)
        XCTAssertEqual(try Scraper().extractPublishDate(soup), "23.07.2022")
    }

    // Мета-тег имеет приоритет и покрывает страницы, где его нет в JSON-LD.
    func testExtractsFromMetaTag() throws {
        let html = """
        <html><head>
        <meta property="article:published_time" content="2021-04-12T18:15:30+00:00" />
        </head><body></body></html>
        """
        let soup = try SwiftSoup.parse(html)
        XCTAssertEqual(try Scraper().extractPublishDate(soup), "12.04.2021")
    }

    func testNoDateReturnsNil() throws {
        let soup = try SwiftSoup.parse("<html><head></head><body>no date here</body></html>")
        XCTAssertNil(try Scraper().extractPublishDate(soup))
    }
}

final class HTMLPlainTextTests: XCTestCase {

    private func plain(_ html: String, select: String = "div") throws -> String {
        let doc = try SwiftSoup.parse(html)
        let root = try doc.select(select).first()!
        return try HTMLPlainText.plainText(from: root)
    }

    func testParagraphsAndUnorderedList() throws {
        let out = try plain("<div><p>Hello   world</p><ul><li>one</li><li>two</li></ul></div>")
        XCTAssertEqual(out, "Hello world\n- one\n- two")
    }

    func testOrderedList() throws {
        let out = try plain("<div><ol><li>a</li><li>b</li></ol></div>")
        XCTAssertEqual(out, "1. a\n2. b")
    }

    func testNestedList() throws {
        let out = try plain("<div><ul><li>parent<ul><li>child</li></ul></li></ul></div>")
        XCTAssertEqual(out, "- parent\n  - child")
    }

    func testTableRows() throws {
        let out = try plain("<div><table><tr><td>A</td><td>B</td></tr><tr><td>C</td><td>D</td></tr></table></div>")
        XCTAssertEqual(out, "A | B\nC | D")
    }

    func testPunctuationSpacingFixed() throws {
        let out = try plain("<div><p>Hello , world .</p></div>")
        XCTAssertEqual(out, "Hello, world.")
    }

    func testHorizontalRule() throws {
        let out = try plain("<div><hr></div>")
        XCTAssertEqual(out, String(repeating: "-", count: 40))
    }

    func testSkipsScriptAndScreenReaderText() throws {
        let out = try plain("<div><script>var x=1;</script><span class=\"sr-only\">hidden</span><p>Visible</p></div>")
        XCTAssertEqual(out, "Visible")
    }
}

final class URLUtilTests: XCTestCase {

    func testCanonicalResolvesRelativeAndAddsTrailingSlash() {
        let out = Scraper.canonicalURL("/product/foo", base: "https://www.subliminalclub.com/shop/")
        XCTAssertEqual(out, "https://www.subliminalclub.com/product/foo/")
    }

    func testCanonicalStripsQueryAndFragment() {
        let out = Scraper.canonicalURL(
            "https://www.subliminalclub.com/product/bar/?utm=1#reviews",
            base: "https://www.subliminalclub.com/shop/"
        )
        XCTAssertEqual(out, "https://www.subliminalclub.com/product/bar/")
    }

    func testCanonicalCollapsesDoubleSlashes() {
        let out = Scraper.canonicalURL(
            "https://www.subliminalclub.com//product//baz",
            base: "https://www.subliminalclub.com/shop/"
        )
        XCTAssertEqual(out, "https://www.subliminalclub.com/product/baz/")
    }

    func testIsProductURL() {
        XCTAssertTrue(Scraper.isProductURL("https://www.subliminalclub.com/product/foo/", expectedHost: "www.subliminalclub.com"))
        XCTAssertFalse(Scraper.isProductURL("https://www.subliminalclub.com/shop/", expectedHost: "www.subliminalclub.com"))
        XCTAssertFalse(Scraper.isProductURL("https://q.subliminalclub.com/product/foo/", expectedHost: "www.subliminalclub.com"))
    }

    func testExtractEntriesReadsTitlesFromListing() throws {
        let html = """
        <ul class="products">
          <li class="product">
            <a class="woocommerce-LoopProduct-link" href="https://www.subliminalclub.com/product/alpha/">
              <h2 class="woocommerce-loop-product__title">Alpha Program</h2>
            </a>
          </li>
          <li class="product">
            <a class="woocommerce-LoopProduct-link" href="https://www.subliminalclub.com/product/beta/">
              <h2 class="woocommerce-loop-product__title">[FREE TITLE] Beta</h2>
            </a>
          </li>
          <li class="product">
            <a class="woocommerce-LoopProduct-link" href="https://www.subliminalclub.com/product/gamma/"><img/></a>
            <h2 class="woocommerce-loop-product__title">Gamma</h2>
          </li>
          <li><a href="https://www.subliminalclub.com/product-category/cores/">Категория</a></li>
        </ul>
        """
        let soup = try SwiftSoup.parse(html)
        let entries = try Scraper.extractEntries(
            from: soup,
            pageURL: "https://www.subliminalclub.com/shop/",
            expectedHost: "www.subliminalclub.com"
        )
        XCTAssertEqual(entries.count, 3)  // категория (не /product/) отброшена
        XCTAssertEqual(entries[0].url, "https://www.subliminalclub.com/product/alpha/")
        XCTAssertEqual(entries[0].title, "Alpha Program")
        XCTAssertEqual(entries[1].title, "[FREE TITLE] Beta")
        XCTAssertEqual(entries[2].title, "Gamma")  // название взято из предка li
    }

    func testRandomPacingDelayWithinRangeAndVaries() {
        var values = Set<Double>()
        for _ in 0..<200 {
            let d = Scraper.randomPacingDelay()
            XCTAssertGreaterThanOrEqual(d, CoreConstants.requestDelayMinSeconds)
            XCTAssertLessThanOrEqual(d, CoreConstants.requestDelayMaxSeconds)
            values.insert(d)
        }
        // Джиттер не должен быть константой — 200 бросков дают заметный разброс.
        XCTAssertGreaterThan(values.count, 50)
    }
}
