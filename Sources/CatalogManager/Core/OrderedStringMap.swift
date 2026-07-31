import Foundation

/// Минимальный упорядоченный словарь String → String. Нужен потому, что
/// Python dict сохраняет порядок вставки, и сериализация товара (to_block)
/// полагается на этот порядок для секций вне стандартного набора.
struct OrderedStringMap {
    private(set) var keys: [String] = []
    private var storage: [String: String] = [:]

    init() {}

    subscript(key: String) -> String? {
        get { storage[key] }
        set {
            if let newValue {
                if storage[key] == nil { keys.append(key) }
                storage[key] = newValue
            } else {
                if storage[key] != nil {
                    storage[key] = nil
                    keys.removeAll { $0 == key }
                }
            }
        }
    }

    func contains(_ key: String) -> Bool {
        storage[key] != nil
    }

    var isEmpty: Bool { keys.isEmpty }
}
