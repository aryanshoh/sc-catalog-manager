import XCTest
@testable import CatalogManager

final class CatalogTextTests: XCTestCase {

    // MARK: - normalizeTitle

    func testNormalizeStripsBracketPrefixAndPunctuation() {
        XCTAssertEqual(CatalogText.normalizeTitle("[FREE] Test Product."), "test product")
        XCTAssertEqual(CatalogText.normalizeTitle("Hello World!!!"), "hello world")
    }

    func testNormalizeUnifiesDashesQuotesAndWhitespace() {
        XCTAssertEqual(CatalogText.normalizeTitle("Café — Déjà"), "café - déjà")
        XCTAssertEqual(CatalogText.normalizeTitle("  Multiple   Spaces  "), "multiple spaces")
        XCTAssertEqual(CatalogText.normalizeTitle("It’s"), "it's")
    }

    // MARK: - parseCategories / parseTags

    func testParseCategories() {
        XCTAssertEqual(CatalogText.parseCategories("Categories: A, B , C"), ["A", "B", "C"])
        XCTAssertEqual(CatalogText.parseCategories("Category: Solo"), ["Solo"])
        XCTAssertEqual(CatalogText.parseCategories(""), [])
    }

    func testParseCategoriesStopsAtTags() {
        XCTAssertEqual(
            CatalogText.parseCategories("Categories: A, B\nTags: x, y"),
            ["A", "B"]
        )
    }

    func testParseTags() {
        XCTAssertEqual(CatalogText.parseTags("Categories: A\nTags: x, y , z"), ["x", "y", "z"])
        XCTAssertEqual(CatalogText.parseTags("Categories: A"), [])
        XCTAssertEqual(CatalogText.parseTags(""), [])
    }

    // MARK: - Round-trip parse <-> serialize

    func testSerializeParseRoundTrip() {
        var s1 = OrderedStringMap()
        s1["Краткое описание"] = "Short A"
        s1["Категории и теги"] = "Categories: X, Y\nTags: t1, t2"
        s1["Полное описание"] = "Full A line 1\nFull A line 2"
        let p1 = Product(title: "Alpha", sections: s1)

        var s2 = OrderedStringMap()
        s2["Полное описание"] = "Only full text"
        let p2 = Product(title: "Beta", sections: s2)

        let header = "Тестовый заголовок каталога"
        let serialized = CatalogText.serializeCatalog([p1, p2], header: header)
        let (parsedHeader, parsed) = CatalogText.parseCatalogText(serialized)

        XCTAssertEqual(parsedHeader, header)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[0].title, "Alpha")
        XCTAssertEqual(parsed[0].sections["Краткое описание"], "Short A")
        XCTAssertEqual(parsed[0].sections["Полное описание"], "Full A line 1\nFull A line 2")
        XCTAssertEqual(parsed[0].categories(), ["X", "Y"])
        XCTAssertEqual(CatalogText.parseTags(parsed[0].sections["Категории и теги"] ?? ""), ["t1", "t2"])
        XCTAssertEqual(parsed[1].title, "Beta")
        XCTAssertEqual(parsed[1].sections["Полное описание"], "Only full text")
    }

    func testSerializeCountsProductsAndEndsWithNewline() {
        let text = CatalogText.serializeCatalog([Product(title: "One"), Product(title: "Two")], header: "H")
        XCTAssertTrue(text.contains("Количество найденных товаров: 2"))
        XCTAssertTrue(text.hasSuffix("\n"))
    }

    func testParseEmptyText() {
        let (header, products) = CatalogText.parseCatalogText("")
        XCTAssertEqual(header, Sites.default.catalogHeader)
        XCTAssertTrue(products.isEmpty)
    }

    func testBlockWithoutKnownHeadersGoesToFullDescription() {
        let raw = "Some Title\n\nJust free-form text without section headers"
        let (_, products) = CatalogText.parseCatalogText(raw)
        XCTAssertEqual(products.count, 1)
        XCTAssertEqual(products[0].title, "Some Title")
        XCTAssertEqual(products[0].sections["Полное описание"], "Just free-form text without section headers")
    }

    // MARK: - signature

    func testSignatureIgnoresCategoryWhitespaceAndOrder() {
        var a = OrderedStringMap(); a["Полное описание"] = "Same"; a["Категории и теги"] = "Categories: A, B"
        var b = OrderedStringMap(); b["Полное описание"] = "Same"; b["Категории и теги"] = "Categories:  B ,  A"
        XCTAssertEqual(Product(title: "T", sections: a).signature(),
                       Product(title: "T", sections: b).signature())
    }

    func testSignatureDiffersOnContent() {
        var a = OrderedStringMap(); a["Полное описание"] = "One"
        var b = OrderedStringMap(); b["Полное описание"] = "Two"
        XCTAssertNotEqual(Product(title: "T", sections: a).signature(),
                          Product(title: "T", sections: b).signature())
    }

    // MARK: - Дата публикации

    func testFormatPublishDateFromISO() {
        // Со смещением +00:00 и с отрицательным — берём календарный день как есть.
        XCTAssertEqual(CatalogText.formatPublishDate(fromISO: "2022-07-23T02:34:02+00:00"), "23.07.2022")
        XCTAssertEqual(CatalogText.formatPublishDate(fromISO: "2021-04-12T18:15:30-04:00"), "12.04.2021")
        // Голая дата тоже принимается.
        XCTAssertEqual(CatalogText.formatPublishDate(fromISO: "2024-12-15"), "15.12.2024")
    }

    func testFormatPublishDateRejectsGarbage() {
        XCTAssertNil(CatalogText.formatPublishDate(fromISO: ""))
        XCTAssertNil(CatalogText.formatPublishDate(fromISO: "not-a-date"))
        XCTAssertNil(CatalogText.formatPublishDate(fromISO: "2022/07/23"))
    }

    func testPublishDateRoundTripsAsSection() {
        var s = OrderedStringMap()
        s["Категории и теги"] = "Categories: A"
        s[CoreConstants.publishDateSection] = "23.07.2022"
        s["Краткое описание"] = "Short"
        let serialized = CatalogText.serializeCatalog([Product(title: "T", sections: s)], header: "H")
        let (_, parsed) = CatalogText.parseCatalogText(serialized)
        XCTAssertEqual(parsed.first?.sections[CoreConstants.publishDateSection], "23.07.2022")
    }

    // MARK: - OrderedStringMap

    func testOrderedMapPreservesInsertionOrder() {
        var m = OrderedStringMap()
        m["b"] = "1"; m["a"] = "2"; m["c"] = "3"
        XCTAssertEqual(m.keys, ["b", "a", "c"])
        m["a"] = "updated"                // перезапись не меняет позицию
        XCTAssertEqual(m.keys, ["b", "a", "c"])
        XCTAssertEqual(m["a"], "updated")
        m["b"] = nil                      // удаление
        XCTAssertEqual(m.keys, ["a", "c"])
    }
}
