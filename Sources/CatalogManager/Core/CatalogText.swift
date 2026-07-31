import Foundation
import CryptoKit

// Парсинг и сериализация txt-формата каталога, а также нормализация названий
// и извлечение категорий/тегов. Порт соответствующих функций catalog_core.py.

enum CatalogText {

    // MARK: - Нормализация и разбор мета-строки

    static func normalizeTitle(_ title: String) -> String {
        var t = RegexPattern("^\\[[^\\]]+\\]\\s*").replacingMatches(in: title, with: "") // убрать [FREE TITLE]
        t = t.replacingOccurrences(of: "\u{2019}", with: "'")  // ’
        t = t.replacingOccurrences(of: "\u{2018}", with: "'")  // ‘
        t = t.replacingOccurrences(of: "\u{2014}", with: "-")  // —
        t = t.replacingOccurrences(of: "\u{2013}", with: "-")  // –
        t = RegexPattern("\\s+").replacingMatches(in: t, with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        // rstrip(".!?")
        while let last = t.last, ".!?".contains(last) {
            t.removeLast()
        }
        return t
    }

    /// Извлекает список категорий из строки вида 'Categories: A , B , C'.
    static func parseCategories(_ raw: String) -> [String] {
        if raw.isEmpty { return [] }
        var text = raw
        if let match = RegexPattern("Categor(?:y|ies)\\s*:\\s*(.*)", options: [.caseInsensitive, .dotMatchesLineSeparators])
            .firstMatch(in: text), let captured = match.group(1) {
            text = captured
        }
        // Отрезаем секцию тегов, если она в той же строке.
        text = RegexPattern("\\bTags?\\s*:", options: [.caseInsensitive]).splitFirst(text)[0]
        return text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func parseTags(_ raw: String) -> [String] {
        if raw.isEmpty { return [] }
        guard let match = RegexPattern("Tags?\\s*:\\s*(.*)", options: [.caseInsensitive, .dotMatchesLineSeparators])
            .firstMatch(in: raw), let captured = match.group(1) else {
            return []
        }
        return captured.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Разбор каталога

    private static let blockSplit = RegexPattern("\\n\\n=+\\n\\n")
    private static let headerSplit = RegexPattern(
        "^(.*?)\\n\\n(Products found:.*?)\\n\\n(.*)$",
        options: [.dotMatchesLineSeparators]
    )

    /// Разбирает текстовый каталог, возвращая (заголовок, список товаров).
    static func parseCatalogText(_ text: String) -> (header: String, products: [Product]) {
        let trimmed = text.strippingNewlines()
        if trimmed.isEmpty {
            return (Sites.default.catalogHeader, [])
        }

        let parts = blockSplit.split(trimmed)
        let first = parts[0]

        let headerTitle: String
        let firstBlock: String
        if let match = headerSplit.firstMatch(in: first),
           let title = match.group(1), let block = match.group(3) {
            headerTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            firstBlock = block
        } else {
            headerTitle = Sites.default.catalogHeader
            firstBlock = first
        }

        let rawBlocks = [firstBlock] + parts.dropFirst()
        var products: [Product] = []
        for rawBlock in rawBlocks {
            let block = rawBlock.strippingNewlines()
            if block.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            products.append(parseBlock(block))
        }
        return (headerTitle, products)
    }

    private static func parseBlock(_ rawBlock: String) -> Product {
        let lines = rawBlock.components(separatedBy: "\n")
        let title = lines[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let rest = lines.dropFirst().joined(separator: "\n").strippingNewlines()

        let knownHeaders = CoreConstants.sectionOrder + ["Description", "Content"]
        let escaped = knownHeaders.map { NSRegularExpression.escapedPattern(for: $0) }
        let headerPattern = RegexPattern("\\n\\n(" + escaped.joined(separator: "|") + ")\\n\\n")

        var sections = OrderedStringMap()
        if !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let searchText = "\n\n" + rest
            let matches = headerPattern.allMatches(in: searchText)
            if matches.isEmpty {
                // Нет узнаваемых заголовков — сохраняем всё как полное описание.
                sections[CoreConstants.fullDescriptionSection] = rest.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                for (index, match) in matches.enumerated() {
                    let name = match.group(1) ?? ""
                    let start = match.range.upperBound
                    let end = index + 1 < matches.count ? matches[index + 1].range.lowerBound : searchText.endIndex
                    let content = String(searchText[start..<end])
                        .strippingNewlines()
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    sections[name] = content
                }
            }
        }

        return Product(title: title, sections: sections)
    }

    // MARK: - Сериализация

    static func serializeCatalog(_ products: [Product], header: String = Sites.default.catalogHeader) -> String {
        let headerLine = "\(header)\n\nProducts found: \(products.count)"
        let blocks = products.map { $0.toBlock() }
        let body = blocks.joined(separator: "\n\n\(CoreConstants.separatorLine)\n\n")
        let content = body.isEmpty ? headerLine : "\(headerLine)\n\n\(body)"
        // content.rstrip() + "\n"
        return content.replacingOccurrences(
            of: "\\s+$", with: "", options: .regularExpression
        ) + "\n"
    }

    // MARK: - Файлы

    static func loadCatalog(_ path: URL) throws -> (header: String, products: [Product]) {
        let text = try String(contentsOf: path, encoding: .utf8)
        return parseCatalogText(text)
    }

    // MARK: - Дата публикации

    /// Преобразует ISO-8601 дату/время (например "2022-07-23T02:34:02+00:00")
    /// в календарную дату формата dd.MM.yyyy ("23.07.2022"). Берёт только
    /// первые 10 символов (YYYY-MM-DD) без пересчёта часового пояса, чтобы день
    /// не «уплывал» из-за смещения. Возвращает nil, если строка не начинается
    /// с корректной даты.
    static func formatPublishDate(fromISO iso: String) -> String? {
        let parts = iso.prefix(10).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isNumber) }) else { return nil }
        return "\(parts[2]).\(parts[1]).\(parts[0])"
    }

    // MARK: - Отпечаток файла (защита от конфликтов записи в общей папке)

    /// SHA-256 переданного текста в hex. Совпадает с `fileFingerprint` файла,
    /// записанного тем же текстом в UTF-8 (без BOM) — как это делает `saveCatalog`.
    static func contentFingerprint(_ text: String) -> String {
        hexDigest(Data(text.utf8))
    }

    /// Отпечаток (SHA-256) содержимого файла на диске, либо `nil`, если файла
    /// нет или он недоступен для чтения. Для облачных провайдеров чтение
    /// материализует актуальную версию файла, поэтому отпечаток отражает то,
    /// что реально лежит на диске сейчас.
    static func fileFingerprint(_ path: URL) -> String? {
        guard let data = try? Data(contentsOf: path) else { return nil }
        return hexDigest(data)
    }

    private static func hexDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func saveCatalog(_ path: URL, products: [Product], header: String = Sites.default.catalogHeader) throws {
        let content = serializeCatalog(products, header: header)
        let fm = FileManager.default
        if fm.fileExists(atPath: path.path) {
            let backup = path.appendingPathExtension("bak")
            // Резервная копия — необязательна: при сбое просто продолжаем запись.
            if let existing = try? String(contentsOf: path, encoding: .utf8) {
                try? existing.write(to: backup, atomically: true, encoding: .utf8)
            }
        }
        try content.write(to: path, atomically: true, encoding: .utf8)
    }
}
