import SwiftUI

// Наблюдаемое состояние приложения и весь управляющий поток — порт класса
// MainWindow из catalog_app_qt.py (без оконного хрома, который в SwiftUI даёт
// нативное окно). Логика открытия/сохранения, актуализации и экспорта здесь.

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Section: String, CaseIterable {
        case menu, actualize, export
    }

    // Каталоги по сайтам
    @Published var catalogStates: [String: CatalogState]
    @Published var activeSiteKey: String = Sites.default.key
    @Published var activeSection: Section = .menu

    // Меню продуктов
    @Published var collapsedCategories: Set<String> = []
    @Published var searchQuery: String = ""
    @Published var selectedProduct: Product?

    // Статус-бар
    @Published var statusText: String = "Ready"

    // Актуализация
    @Published var isRunning = false
    @Published var logText: String = ""
    @Published var progressCurrent = 0
    @Published var progressTotal = 0
    @Published var lastResult: ActualizationResult?
    @Published var showStats = false

    // Sheet «сироты»
    @Published var orphanSheet: OrphanContext?

    // Экспорт
    @Published var exportSuccessName: String?

    // Оформление
    @Published var themeID: ThemeID = .dark {
        didSet {
            guard themeID != oldValue else { return }
            Theme.current = themeID.palette
            AppSettings.setThemeRaw(themeID.rawValue)
            applyWindowChrome()
        }
    }

    private let scraper = Scraper()
    private var cancelFlag = CancelFlag()
    private var worker: Task<Void, Never>?
    private var actualizingSiteKey: String?

    struct OrphanContext: Identifiable {
        let id = UUID()
        let orphans: [Product]
        let result: ActualizationResult
        let targetSiteKey: String
    }

    init() {
        // Тему применяем до построения UI (didSet при инициализации не
        // вызывается, поэтому Theme.current выставляем вручную).
        let savedTheme = AppSettings.themeRaw().flatMap(ThemeID.init(rawValue:)) ?? .dark
        self.themeID = savedTheme
        Theme.current = savedTheme.palette

        var states: [String: CatalogState] = [:]
        for site in Sites.all {
            states[site.key] = CatalogState(siteKey: site.key, header: site.catalogHeader)
        }
        self.catalogStates = states
        loadRememberedCatalogs()
        statusText = "Active site: \(currentSite.shortLabel)"
    }

    // MARK: - Оформление

    func setTheme(_ id: ThemeID) {
        themeID = id
    }

    private func applyWindowChrome() {
        for window in NSApp.windows {
            window.backgroundColor = Theme.current.windowBackground
        }
    }

    // MARK: - Доступ к текущему состоянию

    var currentSite: Site { Sites.site(forKey: activeSiteKey) }

    var currentState: CatalogState {
        get { catalogStates[activeSiteKey] ?? CatalogState(siteKey: activeSiteKey) }
        set { catalogStates[activeSiteKey] = newValue }
    }

    func dirtySiteLabels() -> [String] {
        catalogStates.values
            .filter { $0.dirty }
            .map { Sites.site(forKey: $0.siteKey).shortLabel }
    }

    // MARK: - Переключение сайта / раздела

    func switchSite(_ key: String) {
        guard key != activeSiteKey else { return }
        if isRunning { return }  // не переключаемся во время актуализации
        activeSiteKey = key
        applySiteUI()
    }

    func switchSection(_ section: Section) {
        activeSection = section
    }

    private func applySiteUI() {
        collapsedCategories = []
        searchQuery = ""
        selectedProduct = nil
        if !isRunning {
            resetActualizationView()
        }
        exportSuccessName = nil
        statusText = "Active site: \(currentSite.shortLabel)"
    }

    private func loadRememberedCatalogs() {
        for site in Sites.all {
            guard let path = AppSettings.catalogPath(forSite: site.key),
                  FileManager.default.fileExists(atPath: path.path) else { continue }
            guard let (header, products) = try? CatalogText.loadCatalog(path) else { continue }
            catalogStates[site.key] = CatalogState(
                siteKey: site.key, path: path, header: header, products: products,
                dirty: false, loadedFileHash: CatalogText.fileFingerprint(path)
            )
        }
    }

    // MARK: - Меню продуктов: раскрытие/сворачивание категорий

    func expandAllCategories() {
        collapsedCategories = []
    }

    func collapseAllCategories() {
        // Сворачиваем все категории, видимые при текущем фильтре поиска.
        collapsedCategories = Set(menuGroups().map { $0.category })
    }

    // MARK: - Меню продуктов: группировка

    func menuGroups() -> [(category: String, products: [Product])] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces).lowercased()
        var byCategory: [String: [Product]] = [:]
        var order: [String] = []
        var uncategorized: [Product] = []

        for product in currentState.products {
            if !query.isEmpty && !product.title.lowercased().contains(query) { continue }
            let cats = product.categories()
            if cats.isEmpty {
                uncategorized.append(product)
            } else {
                for cat in cats {
                    if byCategory[cat] == nil { byCategory[cat] = []; order.append(cat) }
                    byCategory[cat]?.append(product)
                }
            }
        }

        var groups: [(String, [Product])] = []
        for category in byCategory.keys.sorted(by: { $0.lowercased() < $1.lowercased() }) {
            let sorted = byCategory[category]!.sorted {
                CatalogText.normalizeTitle($0.title) < CatalogText.normalizeTitle($1.title)
            }
            groups.append((category, sorted))
        }
        if !uncategorized.isEmpty {
            let sorted = uncategorized.sorted {
                CatalogText.normalizeTitle($0.title) < CatalogText.normalizeTitle($1.title)
            }
            groups.append(("Uncategorized", sorted))
        }
        return groups.map { (category: $0.0, products: $0.1) }
    }

    // MARK: - Открытие / сохранение

    func openCatalog() {
        let site = currentSite
        if currentState.dirty {
            let ok = Dialogs.confirm(
                "Unsaved changes",
                "The current catalog “\(site.label)” has unsaved changes. Open another file and lose them?"
            )
            if !ok { return }
        }

        guard let path = Dialogs.openTextFile(title: "Choose a local catalog for “\(site.label)” (txt)") else {
            return
        }

        let filenameLower = path.lastPathComponent.lowercased()
        let looksLikeOtherSite = !filenameLower.contains(site.key)
            && Sites.all.contains { $0.key != site.key && filenameLower.contains($0.key) }
        if looksLikeOtherSite {
            let ok = Dialogs.confirm(
                "Check the selected site",
                "The file “\(path.lastPathComponent)” looks like another site's catalog, but “\(site.label)” is currently selected. "
                + "Open it as the “\(site.label)” catalog anyway?"
            )
            if !ok { return }
        }

        let loaded: (header: String, products: [Product])
        do {
            loaded = try CatalogText.loadCatalog(path)
        } catch {
            Dialogs.error("Read error", "Could not read the file:\n\(error.localizedDescription)")
            return
        }

        catalogStates[site.key] = CatalogState(
            siteKey: site.key, path: path, header: loaded.header, products: loaded.products,
            dirty: false, loadedFileHash: CatalogText.fileFingerprint(path)
        )
        AppSettings.setCatalogPath(path, forSite: site.key)
        applySiteUI()
        statusText = "Opened catalog “\(site.shortLabel)”: \(path.lastPathComponent)"
    }

    func saveCatalog() {
        var state = currentState
        if state.products.isEmpty {
            Dialogs.info("Catalog is empty", "Nothing to save — the catalog is empty.")
            return
        }
        guard let path = state.path else {
            saveCatalogAs()
            return
        }

        // Защита от конфликта записи: если файл в общей папке изменил кто-то с
        // другого устройства после того, как мы его открыли, — не затираем молча.
        if let known = state.loadedFileHash,
           let onDisk = CatalogText.fileFingerprint(path),
           onDisk != known {
            let choice = Dialogs.conflict(
                "Catalog changed on disk",
                "The file “\(path.lastPathComponent)” changed in the shared folder after you opened it — "
                + "someone likely saved it from another device.\n\n"
                + "• “Reload from disk” — open the fresh version (unsaved edits in this catalog will be lost).\n"
                + "• “Overwrite” — save your version on top (edits from the other device will be lost)."
            )
            switch choice {
            case .cancel:
                statusText = "Save canceled: catalog changed on disk"
                return
            case .reload:
                reloadFromDisk(path, forSite: activeSiteKey)
                return
            case .overwrite:
                break  // продолжаем запись ниже
            }
        }

        let content = CatalogText.serializeCatalog(state.products, header: state.header)
        do {
            try CatalogText.saveCatalog(path, products: state.products, header: state.header)
        } catch {
            Dialogs.error("Save error", error.localizedDescription)
            return
        }
        state.dirty = false
        state.loadedFileHash = CatalogText.contentFingerprint(content)
        catalogStates[activeSiteKey] = state
        AppSettings.setCatalogPath(path, forSite: activeSiteKey)
        statusText = "Catalog saved: \(path.lastPathComponent)"
    }

    /// Перечитывает файл с диска в состояние сайта, отбрасывая версию в памяти.
    /// Используется при разрешении конфликта записи («Перезагрузить с диска»).
    private func reloadFromDisk(_ path: URL, forSite siteKey: String) {
        let loaded: (header: String, products: [Product])
        do {
            loaded = try CatalogText.loadCatalog(path)
        } catch {
            Dialogs.error("Read error", "Could not re-read the file:\n\(error.localizedDescription)")
            return
        }
        catalogStates[siteKey] = CatalogState(
            siteKey: siteKey, path: path, header: loaded.header, products: loaded.products,
            dirty: false, loadedFileHash: CatalogText.fileFingerprint(path)
        )
        if siteKey == activeSiteKey {
            selectedProduct = nil
            collapsedCategories = []
        }
        statusText = "Catalog reloaded from disk: \(path.lastPathComponent)"
    }

    func saveCatalogAs() {
        var state = currentState
        let site = currentSite
        if state.products.isEmpty {
            Dialogs.info("Catalog is empty", "Nothing to save — the catalog is empty.")
            return
        }
        let defaultName = state.path?.lastPathComponent ?? "\(site.key)_products.txt"
        guard let path = Dialogs.saveTextFile(title: "Save catalog “\(site.label)” as", defaultName: defaultName) else {
            return
        }
        do {
            try CatalogText.saveCatalog(path, products: state.products, header: state.header)
        } catch {
            Dialogs.error("Save error", error.localizedDescription)
            return
        }
        state.path = path
        state.dirty = false
        state.loadedFileHash = CatalogText.fileFingerprint(path)
        catalogStates[site.key] = state
        AppSettings.setCatalogPath(path, forSite: site.key)
        statusText = "Catalog saved: \(path.lastPathComponent)"
    }

    // MARK: - Актуализация

    private func resetActualizationView() {
        logText = ""
        progressCurrent = 0
        progressTotal = 0
        showStats = false
    }

    func startActualization(mode: ActualizationMode) {
        if isRunning { return }
        let site = currentSite
        let state = currentState

        if state.products.isEmpty && state.path == nil {
            let ok = Dialogs.confirm(
                "No catalog open",
                "No local catalog is open for “\(site.label)”. Start the update with an empty catalog "
                + "(all site products will be added as new)?"
            )
            if !ok { return }
        }

        cancelFlag = CancelFlag()
        isRunning = true
        resetActualizationView()
        activeSection = .actualize
        let modeLabel = mode == .surface ? "surface" : "full"
        statusText = "Update in progress (\(modeLabel))… (\(site.shortLabel))"
        actualizingSiteKey = site.key

        let snapshot = state.products
        let flag = cancelFlag
        let scraper = self.scraper

        worker = Task { [weak self] in
            guard let self else { return }
            let log: @Sendable (String) -> Void = { message in
                Task { @MainActor in self.appendLog(message) }
            }
            let progress: @Sendable (Int, Int) -> Void = { current, total in
                Task { @MainActor in self.setProgress(current, total) }
            }
            do {
                let result = try await actualizeCatalog(
                    mode: mode,
                    localProducts: snapshot, scraper: scraper, site: site,
                    log: log, cancel: flag, progress: progress
                )
                await MainActor.run { self.onActualizationDone(result) }
            } catch is CancelledError {
                await MainActor.run { self.onActualizationCancelled() }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { self.onActualizationError(message) }
            }
            await MainActor.run { self.onWorkerFinished() }
        }
    }

    func cancelActualization() {
        cancelFlag.set()
        appendLog("Stopping at user request…")
    }

    private func appendLog(_ message: String) {
        logText += (logText.isEmpty ? "" : "\n") + message
    }

    private func setProgress(_ current: Int, _ total: Int) {
        progressCurrent = current
        progressTotal = total
    }

    private func onWorkerFinished() {
        isRunning = false
    }

    private func onActualizationDone(_ result: ActualizationResult) {
        appendLog("")
        appendLog("New products added: \(result.added.count)")
        appendLog("Descriptions updated: \(result.updated.count)")
        appendLog("No changes: \(result.unchanged.count)")
        appendLog("Missing on the site (need a decision): \(result.orphans.count)")
        if !result.failed.isEmpty {
            appendLog("Failed to load: \(result.failed.count)")
            for item in result.failed {
                appendLog("  - \(item.url): \(item.error)")
            }
        }
        lastResult = result
        showStats = true

        let targetSiteKey = actualizingSiteKey ?? activeSiteKey
        if result.orphans.isEmpty {
            finishActualization(catalog: result.catalog, targetSiteKey: targetSiteKey)
        } else {
            orphanSheet = OrphanContext(orphans: result.orphans, result: result, targetSiteKey: targetSiteKey)
        }
    }

    /// Вызывается из sheet «сироты»: применить решение пользователя.
    func applyOrphanDecision(context: OrphanContext, toRemove: [Product]) {
        let removeIDs = Set(toRemove.map { ObjectIdentifier($0) })
        let catalog = context.result.catalog.filter { !removeIDs.contains(ObjectIdentifier($0)) }
        if toRemove.isEmpty {
            appendLog("All products missing on the site were kept in the catalog.")
        } else {
            appendLog("Removed from the catalog by user decision: \(toRemove.count)")
        }
        orphanSheet = nil
        finishActualization(catalog: catalog, targetSiteKey: context.targetSiteKey)
    }

    private func finishActualization(catalog: [Product], targetSiteKey: String) {
        var targetState = catalogStates[targetSiteKey] ?? CatalogState(siteKey: targetSiteKey)
        targetState.products = catalog
        targetState.dirty = true
        catalogStates[targetSiteKey] = targetState
        actualizingSiteKey = nil

        if activeSiteKey != targetSiteKey {
            let targetSite = Sites.site(forKey: targetSiteKey)
            appendLog("Switching the active site to “\(targetSite.label)” to show the result.")
            activeSiteKey = targetSiteKey
            applySiteUI()
        } else {
            selectedProduct = nil
        }
        statusText = "Update complete"

        let save = Dialogs.confirm("Update complete", "Save the changes to the catalog file now?")
        if save { saveCatalog() }
    }

    private func onActualizationCancelled() {
        appendLog("Update stopped by the user.")
        statusText = "Update stopped"
    }

    private func onActualizationError(_ message: String) {
        appendLog("Error: \(message)")
        statusText = "Update error"
        Dialogs.error("Update error", message)
    }

    // MARK: - Экспорт

    func exportCatalog() {
        let state = currentState
        let site = currentSite
        if state.products.isEmpty {
            Dialogs.info("Catalog is empty", "Nothing to export — the catalog is empty.")
            return
        }
        guard let path = Dialogs.saveTextFile(title: "Export catalog", defaultName: "\(site.key)_catalog_export.txt") else {
            return
        }
        let ordered = state.products.sorted {
            CatalogText.normalizeTitle($0.title) < CatalogText.normalizeTitle($1.title)
        }
        do {
            try CatalogText.serializeCatalog(ordered, header: state.header)
                .write(to: path, atomically: true, encoding: .utf8)
        } catch {
            Dialogs.error("Export error", error.localizedDescription)
            return
        }
        exportSuccessName = path.lastPathComponent
        statusText = "Exported \(ordered.count) products"
    }

    // MARK: - Закрытие окна

    /// Возвращает true, если окно можно закрыть.
    func confirmClose() -> Bool {
        if isRunning {
            let ok = Dialogs.confirm(
                "Update in progress",
                "An update is still in progress. Interrupt it and quit the app?"
            )
            if !ok { return false }
            cancelFlag.set()
        }
        let dirty = dirtySiteLabels()
        if !dirty.isEmpty {
            let ok = Dialogs.confirm(
                "Unsaved changes",
                "There are unsaved changes in the catalog: " + dirty.joined(separator: ", ") + ". Quit without saving?"
            )
            if !ok { return false }
        }
        return true
    }
}
