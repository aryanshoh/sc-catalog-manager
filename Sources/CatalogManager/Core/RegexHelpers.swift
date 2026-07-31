import Foundation

// Небольшой слой поверх NSRegularExpression, повторяющий те операции над
// строками, что делает Python-версия через модуль `re` (search / split /
// sub / finditer). Держим его отдельно, чтобы бизнес-логика в Core читалась
// так же близко к оригиналу, как это возможно в Swift.

struct RegexMatch {
    let range: Range<String.Index>
    let groups: [String?]

    func group(_ index: Int) -> String? {
        guard index < groups.count else { return nil }
        return groups[index]
    }
}

struct RegexPattern {
    private let regex: NSRegularExpression

    init(_ pattern: String, options: NSRegularExpression.Options = []) {
        // Паттерны в этом проекте статические и заведомо валидные — падать
        // на этапе инициализации допустимо (как и у скомпилированного re в Python).
        self.regex = try! NSRegularExpression(pattern: pattern, options: options)
    }

    private func nsRange(_ string: String) -> NSRange {
        NSRange(string.startIndex..<string.endIndex, in: string)
    }

    private func makeMatch(_ result: NSTextCheckingResult, in string: String) -> RegexMatch? {
        guard let full = Range(result.range, in: string) else { return nil }
        var groups: [String?] = []
        for i in 0..<result.numberOfRanges {
            if let r = Range(result.range(at: i), in: string) {
                groups.append(String(string[r]))
            } else {
                groups.append(nil)
            }
        }
        return RegexMatch(range: full, groups: groups)
    }

    /// Аналог re.search — первое совпадение в строке (или nil).
    func firstMatch(in string: String) -> RegexMatch? {
        guard let result = regex.firstMatch(in: string, range: nsRange(string)) else { return nil }
        return makeMatch(result, in: string)
    }

    /// Аналог re.finditer — все непересекающиеся совпадения по порядку.
    func allMatches(in string: String) -> [RegexMatch] {
        regex.matches(in: string, range: nsRange(string)).compactMap { makeMatch($0, in: string) }
    }

    /// Аналог bool(re.search(...)).
    func matches(_ string: String) -> Bool {
        firstMatch(in: string) != nil
    }

    /// Аналог re.sub(pattern, template, string). Шаблон — синтаксис ICU ($1 и т.п.).
    func replacingMatches(in string: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: string, range: nsRange(string), withTemplate: template
        )
    }

    /// Аналог re.split(pattern, string) без ограничения на число разбиений.
    func split(_ string: String) -> [String] {
        var pieces: [String] = []
        var lastEnd = string.startIndex
        for match in allMatches(in: string) {
            pieces.append(String(string[lastEnd..<match.range.lowerBound]))
            lastEnd = match.range.upperBound
        }
        pieces.append(String(string[lastEnd...]))
        return pieces
    }

    /// Аналог re.split(pattern, string, maxsplit=1) — разбить по первому совпадению.
    func splitFirst(_ string: String) -> [String] {
        guard let match = firstMatch(in: string) else { return [string] }
        return [
            String(string[string.startIndex..<match.range.lowerBound]),
            String(string[match.range.upperBound...])
        ]
    }
}

extension String {
    /// Эквивалент " ".join(text.split()) в Python: схлопывает любые пробельные
    /// последовательности в один пробел и обрезает края.
    func normalizedWhitespace() -> String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    func strippingNewlines() -> String {
        trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
    }
}
