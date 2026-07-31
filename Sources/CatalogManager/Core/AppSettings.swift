import Foundation

// Персистентное хранилище настроек — сейчас только пути к последним открытым
// каталогам по каждому сайту. Формат и расположение файла те же, что у
// Python-версии (app_settings.py), поэтому настройки взаимозаменяемы.

enum AppSettings {
    private static let settingsDir: URL = {
        #if os(macOS)
        // Тот же путь, что у Python-версии — настройки взаимозаменяемы.
        return FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SubliminalClub Catalog Manager", isDirectory: true)
        #else
        // iOS: песочница. Application Support внутри контейнера приложения.
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )) ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("SubliminalClub Catalog Manager", isDirectory: true)
        #endif
    }()
    private static let settingsFile = settingsDir.appendingPathComponent("settings.json")

    private struct Stored: Codable {
        var catalog_paths: [String: String]?
        var theme: String?
        // iOS: URL из документ-пикера непереносим между запусками (песочница),
        // поэтому храним security-scoped закладку в base64. Игнорируется на macOS.
        var catalog_bookmarks: [String: String]?
    }

    private static func load() -> Stored {
        guard let data = try? Data(contentsOf: settingsFile),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            return Stored(catalog_paths: [:])
        }
        return stored
    }

    private static func save(_ stored: Stored) {
        // Настройки — не критичные данные: при сбое просто не сохраняем.
        try? FileManager.default.createDirectory(at: settingsDir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(stored) {
            try? data.write(to: settingsFile)
        }
    }

    static func catalogPath(forSite siteKey: String) -> URL? {
        guard let raw = load().catalog_paths?[siteKey], !raw.isEmpty else { return nil }
        return URL(fileURLWithPath: raw)
    }

    static func setCatalogPath(_ path: URL, forSite siteKey: String) {
        var stored = load()
        var paths = stored.catalog_paths ?? [:]
        paths[siteKey] = path.path
        stored.catalog_paths = paths
        save(stored)
    }

    // Тема хранится как строка (raw value ThemeID) — Core не зависит от UI-слоя.
    static func themeRaw() -> String? {
        load().theme
    }

    static func setThemeRaw(_ raw: String) {
        var stored = load()
        stored.theme = raw
        save(stored)
    }

    // MARK: - iOS: security-scoped закладки на последний каталог

    static func catalogBookmark(forSite siteKey: String) -> Data? {
        guard let raw = load().catalog_bookmarks?[siteKey], !raw.isEmpty else { return nil }
        return Data(base64Encoded: raw)
    }

    static func setCatalogBookmark(_ data: Data, forSite siteKey: String) {
        var stored = load()
        var marks = stored.catalog_bookmarks ?? [:]
        marks[siteKey] = data.base64EncodedString()
        stored.catalog_bookmarks = marks
        save(stored)
    }

    static func clearCatalogBookmark(forSite siteKey: String) {
        var stored = load()
        stored.catalog_bookmarks?[siteKey] = nil
        save(stored)
    }
}
