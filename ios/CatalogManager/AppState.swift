import SwiftUI

// Наблюдаемое состояние и управляющий поток iOS-версии — порт AppState из
// macOS-версии. Отличия только в платформенном слое:
//   • модальные NSAlert  → асинхронный DialogCoordinator (await dialogs.confirm)
//   • NSOpenPanel        → .fileImporter (+ security-scoped доступ и закладки)
//   • NSSavePanel        → .fileExporter (CatalogTextDocument)
//   • оконный хром/закрытие — отсутствует (на iOS его нет)
// Бизнес-логика (группировка меню, актуализация, экспорт) не изменилась.

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Section: String, CaseIterable {
        case menu, actualize, export
    }

    let dialogs = DialogCoordinator()

    // Каталоги по сайтам
    @Published var catalogStates: [String: CatalogState]
    @Published var activeSiteKey: String = Sites.default.key

    // Меню продуктов
    @Published var collapsedCategories: Set<String> = []
    @Published var searchQuery: String = ""
    @Published var selectedProduct: Product?

    // Статус
    @Published var statusText: String = "Готово"

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

    // Файловые пикеры (SwiftUI)
    @Published var fileImporterPresented = false
    @Published var exporterPresented = false
    @Published var exportDocument = CatalogTextDocument(text: "")
    @Published var exportFilename = "catalog.txt"
    enum ExportMode { case saveAs, export }
    private var exportMode: ExportMode = .export

    // Оформление
    @Published var themeID: ThemeID = .dark {
        didSet {
            guard themeID != oldValue else { return }
            Theme.current = themeID.palette
            AppSettings.setThemeRaw(themeID.rawValue)
        }
    }

    private let scraper = Scraper()
    private var cancelFlag = CancelFlag()
    private var worker: Task<Void, Never>?
    private var actualizingSiteKey: String?
    /// URL'ы с удерживаемым security-scoped доступом (для записи «Сохранить»).
    private var scopedURLs: [String: URL] = [:]

    struct OrphanContext: Identifiable {
        let id = UUID()
        let orphans: [Product]
        let result: ActualizationResult
        let targetSiteKey: String
    }

    init() {
        let savedTheme = AppSettings.themeRaw().flatMap(ThemeID.init(rawValue:)) ?? .dark
        self.themeID = savedTheme
        Theme.current = savedTheme.palette

        var states: [String: CatalogState] = [:]
        for site in Sites.all {
            states[site.key] = CatalogState(siteKey: site.key, header: site.catalogHeader)
        }
        self.catalogStates = states
        loadRememberedCatalogs()
        statusText = "Активный сайт: \(currentSite.shortLabel)"
    }

    // MARK: - Оформление

    func setTheme(_ id: ThemeID) { themeID = id }

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
        if isRunning { return }
        activeSiteKey = key
        applySiteUI()
    }

    private func applySiteUI() {
        collapsedCategories = []
        searchQuery = ""
        selectedProduct = nil
        if !isRunning { resetActualizationView() }
        exportSuccessName = nil
        statusText = "Активный сайт: \(currentSite.shortLabel)"
    }

    private func loadRememberedCatalogs() {
        for site in Sites.all {
            guard let data = AppSettings.catalogBookmark(forSite: site.key) else { continue }
            var stale = false
            guard let url = try? URL(
                resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale
            ) else {
                AppSettings.clearCatalogBookmark(forSite: site.key)
                continue
            }
            let scoped = url.startAccessingSecurityScopedResource()
            guard let loaded = try? CatalogText.loadCatalog(url) else {
                if scoped { url.stopAccessingSecurityScopedResource() }
                continue
            }
            scopedURLs[site.key] = url  // удерживаем доступ на время сессии
            catalogStates[site.key] = CatalogState(
                siteKey: site.key, path: url, header: loaded.header, products: loaded.products,
                dirty: false, loadedFileHash: CatalogText.fileFingerprint(url)
            )
            if stale, let fresh = try? url.bookmarkData() {
                AppSettings.setCatalogBookmark(fresh, forSite: site.key)
            }
        }
    }

    // MARK: - Меню продуктов

    func expandAllCategories() { collapsedCategories = [] }

    func collapseAllCategories() {
        collapsedCategories = Set(menuGroups().map { $0.category })
    }

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
            groups.append(("Без категории", sorted))
        }
        return groups.map { (category: $0.0, products: $0.1) }
    }

    // MARK: - Открытие

    /// Кнопка «Открыть»: проверка несохранённого, затем показ документ-пикера.
    func requestOpenCatalog() async {
        let site = currentSite
        if currentState.dirty {
            let ok = await dialogs.confirm(
                "Несохранённые изменения",
                "В текущем каталоге «\(site.label)» есть несохранённые изменения. Открыть другой файл и потерять их?"
            )
            if !ok { return }
        }
        fileImporterPresented = true
    }

    /// Обработка выбранного в .fileImporter файла.
    func handlePickedCatalog(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            Task { await dialogs.error("Ошибка выбора", error.localizedDescription) }
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await importCatalog(from: url) }
        }
    }

    private func importCatalog(from url: URL) async {
        let site = currentSite
        let scoped = url.startAccessingSecurityScopedResource()

        let filenameLower = url.lastPathComponent.lowercased()
        let looksLikeOtherSite = !filenameLower.contains(site.key)
            && Sites.all.contains { $0.key != site.key && filenameLower.contains($0.key) }
        if looksLikeOtherSite {
            let ok = await dialogs.confirm(
                "Проверьте выбор сайта",
                "Файл «\(url.lastPathComponent)» похож на каталог другого сайта, а сейчас выбран «\(site.label)». "
                + "Открыть его как каталог «\(site.label)» всё равно?"
            )
            if !ok { if scoped { url.stopAccessingSecurityScopedResource() }; return }
        }

        let loaded: (header: String, products: [Product])
        do {
            loaded = try CatalogText.loadCatalog(url)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            await dialogs.error("Ошибка чтения", "Не удалось прочитать файл:\n\(error.localizedDescription)")
            return
        }

        adoptURL(url, forSite: site.key)  // удерживаем доступ + закладка
        catalogStates[site.key] = CatalogState(
            siteKey: site.key, path: url, header: loaded.header, products: loaded.products,
            dirty: false, loadedFileHash: CatalogText.fileFingerprint(url)
        )
        applySiteUI()
        statusText = "Открыт каталог «\(site.shortLabel)»: \(url.lastPathComponent)"
    }

    /// Начинает удерживать security-scoped доступ к url и сохраняет закладку.
    private func adoptURL(_ url: URL, forSite siteKey: String) {
        if let previous = scopedURLs[siteKey], previous != url {
            previous.stopAccessingSecurityScopedResource()
        }
        _ = url.startAccessingSecurityScopedResource()
        scopedURLs[siteKey] = url
        if let bookmark = try? url.bookmarkData() {
            AppSettings.setCatalogBookmark(bookmark, forSite: siteKey)
        }
    }

    // MARK: - Сохранение

    func saveCatalog() async {
        let state = currentState
        if state.products.isEmpty {
            await dialogs.info("Каталог пуст", "Нечего сохранять — каталог пуст.")
            return
        }
        guard let path = state.path else {
            saveCatalogAs()
            return
        }

        // Защита от конфликта записи: если файл в общей папке изменил кто-то с
        // другого устройства после того, как мы его открыли, — не затираем молча.
        // `fileFingerprint` читает актуальное содержимое (для облачных провайдеров
        // это материализует свежую версию), поэтому сравнение достоверно.
        if let known = state.loadedFileHash,
           let onDisk = CatalogText.fileFingerprint(path),
           onDisk != known {
            let choice = await dialogs.conflict(
                "Каталог изменён на диске",
                "Файл «\(path.lastPathComponent)» изменился в общей папке после того, как вы его открыли — "
                + "вероятно, его сохранил кто-то с другого устройства.\n\n"
                + "• «Перезагрузить с диска» — открыть свежую версию (несохранённые правки в этом каталоге пропадут).\n"
                + "• «Перезаписать» — сохранить вашу версию поверх (правки с другого устройства пропадут)."
            )
            switch choice {
            case .cancel:
                statusText = "Сохранение отменено: каталог изменён на диске"
                return
            case .reload:
                await reloadFromDisk(path, forSite: activeSiteKey)
                return
            case .overwrite:
                break  // продолжаем запись ниже
            }
        }

        let content = CatalogText.serializeCatalog(state.products, header: state.header)
        do {
            try CatalogText.saveCatalog(path, products: state.products, header: state.header)
        } catch {
            await dialogs.error("Ошибка сохранения", error.localizedDescription)
            return
        }
        markSaved(forSite: activeSiteKey, fileHash: CatalogText.contentFingerprint(content))
        statusText = "Каталог сохранён: \(path.lastPathComponent)"
    }

    /// Перечитывает файл с диска в состояние сайта, отбрасывая версию в памяти.
    /// Используется при разрешении конфликта записи («Перезагрузить с диска»).
    private func reloadFromDisk(_ url: URL, forSite siteKey: String) async {
        let loaded: (header: String, products: [Product])
        do {
            loaded = try CatalogText.loadCatalog(url)
        } catch {
            await dialogs.error("Ошибка чтения", "Не удалось перечитать файл:\n\(error.localizedDescription)")
            return
        }
        catalogStates[siteKey] = CatalogState(
            siteKey: siteKey, path: url, header: loaded.header, products: loaded.products,
            dirty: false, loadedFileHash: CatalogText.fileFingerprint(url)
        )
        if siteKey == activeSiteKey {
            selectedProduct = nil
            collapsedCategories = []
        }
        statusText = "Каталог перезагружен с диска: \(url.lastPathComponent)"
    }

    /// «Сохранить как…» — через системный экспорт документа.
    func saveCatalogAs() {
        let state = currentState
        let site = currentSite
        if state.products.isEmpty {
            Task { await dialogs.info("Каталог пуст", "Нечего сохранять — каталог пуст.") }
            return
        }
        exportMode = .saveAs
        exportDocument = CatalogTextDocument(
            text: CatalogText.serializeCatalog(state.products, header: state.header)
        )
        exportFilename = state.path?.lastPathComponent ?? "\(site.key)_products.txt"
        exporterPresented = true
    }

    private func markSaved(forSite siteKey: String, fileHash: String? = nil) {
        guard var state = catalogStates[siteKey] else { return }
        state.dirty = false
        if let fileHash { state.loadedFileHash = fileHash }
        catalogStates[siteKey] = state
    }

    // MARK: - Экспорт

    func exportCatalog() {
        let state = currentState
        let site = currentSite
        if state.products.isEmpty {
            Task { await dialogs.info("Каталог пуст", "Нечего экспортировать — каталог пуст.") }
            return
        }
        let ordered = state.products.sorted {
            CatalogText.normalizeTitle($0.title) < CatalogText.normalizeTitle($1.title)
        }
        exportMode = .export
        exportDocument = CatalogTextDocument(
            text: CatalogText.serializeCatalog(ordered, header: state.header)
        )
        exportFilename = "\(site.key)_catalog_export.txt"
        exporterPresented = true
    }

    /// Обработка результата .fileExporter (общий для «Сохранить как…» и «Экспорт»).
    func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            // Отмена пользователя приходит как ошибка CocoaError.userCancelled — молчим.
            if (error as? CocoaError)?.code == .userCancelled { return }
            Task { await dialogs.error("Ошибка сохранения", error.localizedDescription) }
        case .success(let url):
            switch exportMode {
            case .saveAs:
                adoptURL(url, forSite: activeSiteKey)
                var state = currentState
                state.path = url
                state.dirty = false
                state.loadedFileHash = CatalogText.fileFingerprint(url)
                catalogStates[activeSiteKey] = state
                statusText = "Каталог сохранён: \(url.lastPathComponent)"
            case .export:
                exportSuccessName = url.lastPathComponent
                statusText = "Экспортировано в \(url.lastPathComponent)"
            }
        }
    }

    // MARK: - Актуализация

    private func resetActualizationView() {
        logText = ""
        progressCurrent = 0
        progressTotal = 0
        showStats = false
    }

    func startActualization(mode: ActualizationMode) async {
        if isRunning { return }
        let site = currentSite
        let state = currentState

        if state.products.isEmpty && state.path == nil {
            let ok = await dialogs.confirm(
                "Каталог не открыт",
                "Для сайта «\(site.label)» локальный каталог не открыт. Начать актуализацию с пустого каталога "
                + "(все товары сайта будут добавлены как новые)?"
            )
            if !ok { return }
        }

        cancelFlag = CancelFlag()
        isRunning = true
        resetActualizationView()
        let modeLabel = mode == .surface ? "поверхностная" : "полная"
        statusText = "Актуализация выполняется (\(modeLabel))… (\(site.shortLabel))"
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
                await self.onActualizationDone(result)
            } catch is CancelledError {
                // Task унаследовал изоляцию MainActor (создан в @MainActor-методе),
                // поэтому синхронные MainActor-методы вызываются без await.
                self.onActualizationCancelled()
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await self.onActualizationError(message)
            }
            self.onWorkerFinished()
        }
    }

    func cancelActualization() {
        cancelFlag.set()
        appendLog("Останавливаю по запросу пользователя…")
    }

    private func appendLog(_ message: String) {
        logText += (logText.isEmpty ? "" : "\n") + message
    }

    private func setProgress(_ current: Int, _ total: Int) {
        progressCurrent = current
        progressTotal = total
    }

    private func onWorkerFinished() { isRunning = false }

    private func onActualizationDone(_ result: ActualizationResult) async {
        appendLog("")
        appendLog("Добавлено новых товаров: \(result.added.count)")
        appendLog("Обновлено описаний: \(result.updated.count)")
        appendLog("Без изменений: \(result.unchanged.count)")
        appendLog("Отсутствуют на сайте (требуют решения): \(result.orphans.count)")
        if !result.failed.isEmpty {
            appendLog("Не удалось загрузить: \(result.failed.count)")
            for item in result.failed {
                appendLog("  - \(item.url): \(item.error)")
            }
        }
        lastResult = result
        showStats = true

        let targetSiteKey = actualizingSiteKey ?? activeSiteKey
        if result.orphans.isEmpty {
            await finishActualization(catalog: result.catalog, targetSiteKey: targetSiteKey)
        } else {
            orphanSheet = OrphanContext(orphans: result.orphans, result: result, targetSiteKey: targetSiteKey)
        }
    }

    /// Вызывается из sheet «сироты»: применить решение пользователя.
    func applyOrphanDecision(context: OrphanContext, toRemove: [Product]) async {
        let removeIDs = Set(toRemove.map { ObjectIdentifier($0) })
        let catalog = context.result.catalog.filter { !removeIDs.contains(ObjectIdentifier($0)) }
        if toRemove.isEmpty {
            appendLog("Все отсутствующие на сайте товары оставлены в каталоге.")
        } else {
            appendLog("Удалено из каталога по решению пользователя: \(toRemove.count)")
        }
        orphanSheet = nil
        await finishActualization(catalog: catalog, targetSiteKey: context.targetSiteKey)
    }

    private func finishActualization(catalog: [Product], targetSiteKey: String) async {
        var targetState = catalogStates[targetSiteKey] ?? CatalogState(siteKey: targetSiteKey)
        targetState.products = catalog
        targetState.dirty = true
        catalogStates[targetSiteKey] = targetState
        actualizingSiteKey = nil

        if activeSiteKey != targetSiteKey {
            let targetSite = Sites.site(forKey: targetSiteKey)
            appendLog("Переключаю активный сайт на «\(targetSite.label)», чтобы показать результат.")
            activeSiteKey = targetSiteKey
            applySiteUI()
        } else {
            selectedProduct = nil
        }
        statusText = "Актуализация завершена"

        let save = await dialogs.confirm("Актуализация завершена", "Сохранить изменения в файл каталога сейчас?")
        if save { await saveCatalog() }
    }

    private func onActualizationCancelled() {
        appendLog("Актуализация остановлена пользователем.")
        statusText = "Актуализация остановлена"
    }

    private func onActualizationError(_ message: String) async {
        appendLog("Ошибка: \(message)")
        statusText = "Ошибка актуализации"
        await dialogs.error("Ошибка актуализации", message)
    }
}
