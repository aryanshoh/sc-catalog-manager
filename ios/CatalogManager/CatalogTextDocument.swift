import SwiftUI
import UniformTypeIdentifiers

// Документ для .fileExporter — обёртка над готовым txt-содержимым каталога.
// Используется при «Сохранить как…» и «Экспорт», где на iOS вместо NSSavePanel
// применяется системный экспорт документа.

struct CatalogTextDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    static var writableContentTypes: [UTType] { [.plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents {
            text = String(decoding: data, as: UTF8.self)
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
