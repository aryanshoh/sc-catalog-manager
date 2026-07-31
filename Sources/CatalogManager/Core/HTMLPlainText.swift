import Foundation
import SwiftSoup

// Преобразование HTML описания товара в аккуратный плоский текст — порт
// функций _plain_lines_from_html / _plain_list_lines и т.п. из catalog_core.py.
// BeautifulSoup ↦ SwiftSoup: node.children ↦ getChildNodes(), NavigableString ↦
// TextNode, Tag ↦ Element, get_text(" ", strip=True) ↦ Element.text().

enum HTMLPlainText {

    static let skipTags: Set<String> = [
        "script", "style", "noscript", "form", "button", "input",
        "select", "option", "textarea", "svg", "iframe",
    ]

    static let blockTags: Set<String> = [
        "address", "article", "aside", "blockquote", "div", "dl", "fieldset",
        "figure", "figcaption", "footer", "form", "h1", "h2", "h3", "h4", "h5",
        "h6", "header", "hr", "li", "main", "nav", "ol", "p", "pre", "section",
        "table", "ul",
    ]

    private static let punctuationSpaceRegex = RegexPattern("\\s+([,.;:!?])")

    // MARK: - Мелкие помощники

    static func textOrNil(_ element: Element?) throws -> String? {
        guard let element else { return nil }
        let text = try element.text().normalizedWhitespace()
        return text.isEmpty ? nil : text
    }

    private static func directChildElements(_ element: Element, tags: Set<String>) -> [Element] {
        element.children().array().filter { tags.contains($0.tagName()) }
    }

    private static func listItemPlainText(_ item: Element) throws -> String {
        var parts: [String] = []
        for child in item.getChildNodes() {
            if let element = child as? Element {
                let tag = element.tagName()
                if tag == "ul" || tag == "ol" { continue }
                if !skipTags.contains(tag) {
                    let text = try element.text().normalizedWhitespace()
                    if !text.isEmpty { parts.append(text) }
                }
            } else if let textNode = child as? TextNode {
                let text = textNode.getWholeText().normalizedWhitespace()
                if !text.isEmpty { parts.append(text) }
            }
        }
        return parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func plainListLines(_ listTag: Element, level: Int = 0) throws -> [String] {
        var lines: [String] = []
        let ordered = listTag.tagName() == "ol"
        let items = listTag.children().array().filter { $0.tagName() == "li" }
        for (offset, item) in items.enumerated() {
            let text = try listItemPlainText(item)
            if !text.isEmpty {
                let prefix = ordered ? "\(offset + 1)." : "-"
                lines.append("\(String(repeating: "  ", count: level))\(prefix) \(text)")
            }
            for nested in directChildElements(item, tags: ["ul", "ol"]) {
                lines.append(contentsOf: try plainListLines(nested, level: level + 1))
            }
        }
        return lines
    }

    private static func hasBlockChildren(_ tag: Element) -> Bool {
        tag.children().array().contains { blockTags.contains($0.tagName()) }
    }

    private static func cleanPlainText(_ value: String) -> String {
        value.components(separatedBy: .newlines)
            .map { $0.normalizedWhitespace() }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: - Основной обход

    private static func plainLines(_ root: Element, level: Int = 0) throws -> [String] {
        var lines: [String] = []
        for node in root.getChildNodes() {
            if let textNode = node as? TextNode {
                let text = textNode.getWholeText().normalizedWhitespace()
                if !text.isEmpty { lines.append(text) }
                continue
            }
            guard let element = node as? Element else { continue }
            let name = element.tagName()
            if skipTags.contains(name) { continue }

            let classAttr = (try? element.attr("class")) ?? ""
            let classes = Set(classAttr.split(whereSeparator: { $0.isWhitespace }).map(String.init))
            if classes.contains("screen-reader-text") || classes.contains("sr-only") || classes.contains("hidden") {
                continue
            }

            switch name {
            case "h1", "h2", "h3", "h4", "h5", "h6", "p", "blockquote":
                if var text = try textOrNil(element) {
                    text = punctuationSpaceRegex.replacingMatches(in: text, with: "$1")
                    lines.append(text)
                }
            case "ul", "ol":
                lines.append(contentsOf: try plainListLines(element, level: level))
            case "table":
                for row in try element.select("tr").array() {
                    let cells = directChildElements(row, tags: ["th", "td"])
                    let values = try cells.map { try $0.text().normalizedWhitespace() }.filter { !$0.isEmpty }
                    if !values.isEmpty {
                        lines.append(values.joined(separator: " | "))
                    }
                }
            case "pre":
                let text = cleanPlainText(try element.text())
                if !text.isEmpty {
                    lines.append(contentsOf: text.components(separatedBy: "\n"))
                }
            case "figure":
                if let caption = try element.select("figcaption").first(), let text = try textOrNil(caption) {
                    lines.append(text)
                }
            case "img":
                continue
            case "hr":
                lines.append(String(repeating: "-", count: 40))
            default:
                if hasBlockChildren(element) {
                    lines.append(contentsOf: try plainLines(element, level: level))
                } else if let text = try textOrNil(element) {
                    lines.append(text)
                }
            }
        }
        return lines
    }

    static func plainText(from root: Element) throws -> String {
        try plainLines(root).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
