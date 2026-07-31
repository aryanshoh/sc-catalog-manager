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
        statusText = "Активный сайт: \(currentSite.shortLabel)"
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
        statusText = "Активный сайт: \(currentSite.shortLabel)"
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
            groups.append(("Без категории", sorted))
        }
        return groups.map { (category: $0.0, products: $0.1) }
    }

    // MARK: - Открытие / сохранение

    func openCatalog() {
        let site = currentSite
        if currentState.dirty {
            let ok = Dialogs.confirm(
                "Несохранённые изменения",
                "В текущем каталоге «\(site.label)» есть несохранённые изменения. Открыть другой файл и потерять их?"
            )
            if !ok { return }
        }

        guard let path = Dialogs.openTextFile(title: "Выберите локальный каталог для «\(site.label)» (txt)") else {
            return
        }

        let filenameLower = path.lastPathComponent.lowercased()
        let looksLikeOtherSite = !filenameLower.contains(site.key)
            && Sites.all.contains { $0.key != site.key && filenameLower.contains($0.key) }
        if looksLikeOtherSite {
            let ok = Dialogs.confirm(
                "Проверьте выбор сайта",
                "Файл «\(path.lastPathComponent)» похож на каталог другого сайта, а сейчас выбран «\(site.label)». "
                + "Открыть его как каталог «\(site.label)» всё равно?"
            )
            if !ok { return }
        }

        let loaded: (header: String, products: [Product])
        do {
            loaded = try CatalogText.loadCatalog(path)
        } catch {
            Dialogs.error("Ошибка чтения", "Не удалось прочитать файл:\n\(error.localizedDescription)")
            return
        }

        catalogStates[site.key] = CatalogState(
            siteKey: site.key, path: path, header: loaded.header, products: loaded.products,
            dirty: false, loadedFileHash: CatalogText.fileFingerprint(path)
        )
        AppSettings.setCatalogPath(path, forSite: site.key)
        applySiteUI()
        statusText = "Открыт каталог «\(site.shortLabel)»: \(path.lastPathComponent)"
    }

    func saveCatalog() {
        var state = currentState
        if state.products.isEmpty {
            Dialogs.info("Каталог пуст", "Нечего сохранять — каталог пуст.")
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
            Dialogs.error("Ошибка сохранения", error.localizedDescription)
            return
        }
        state.dirty = false
        state.loadedFileHash = CatalogText.contentFingerprint(content)
        catalogStates[activeSiteKey] = state
        AppSettings.setCatalogPath(path, forSite: activeSiteKey)
        statusText = "Каталог сохранён: \(path.lastPathComponent)"
    }

    /// Перечитывает файл с диска в состояние сайта, отбрасывая версию в памяти.
    /// Используется при разрешении конфликта записи («Перезагрузить с диска»).
    private func reloadFromDisk(_ path: URL, forSite siteKey: String) {
        let loaded: (header: String, products: [Product])
        do {
            loaded = try CatalogText.loadCatalog(path)
        } catch {
            Dialogs.error("Ошибка чтения", "Не удалось перечитать файл:\n\(error.localizedDescription)")
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
        statusText = "Каталог перезагружен с диска: \(path.lastPathComponent)"
    }

    func saveCatalogAs() {
        var state = currentState
        let site = currentSite
        if state.products.isEmpty {
            Dialogs.info("Каталог пуст", "Нечего сохранять — каталог пуст.")
            return
        }
        let defaultName = state.path?.lastPathComponent ?? "\(site.key)_products.txt"
        guard let path = Dialogs.saveTextFile(title: "Сохранить каталог «\(site.label)» как", defaultName: defaultName) else {
            return
        }
        do {
            try CatalogText.saveCatalog(path, products: state.products, header: state.header)
        } catch {
            Dialogs.error("Ошибка сохранения", error.localizedDescription)
            return
        }
        state.path = path
        state.dirty = false
        state.loadedFileHash = CatalogText.fileFingerprint(path)
        catalogStates[site.key] = state
        AppSettings.setCatalogPath(path, forSite: site.key)
        statusText = "Каталог сохранён: \(path.lastPathComponent)"
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
                "Каталог не открыт",
                "Для сайта «\(site.label)» локальный каталог не открыт. Начать актуализацию с пустого каталога "
                + "(все товары сайта будут добавлены как новые)?"
            )
            if !ok { return }
        }

        cancelFlag = CancelFlag()
        isRunning = true
        resetActualizationView()
        activeSection = .actualize
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
        appendLog("Останавливаю по запросу пользователя…")
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
            appendLog("Все отсутствующие на сайте товары оставлены в каталоге.")
        } else {
            appendLog("Удалено из каталога по решению пользователя: \(toRemove.count)")
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
            appendLog("Переключаю активный сайт на «\(targetSite.label)», чтобы показать результат.")
            activeSiteKey = targetSiteKey
            applySiteUI()
        } else {
            selectedProduct = nil
        }
        statusText = "Актуализация завершена"

        let save = Dialogs.confirm("Актуализация завершена", "Сохранить изменения в файл каталога сейчас?")
        if save { saveCatalog() }
    }

    private func onActualizationCancelled() {
        appendLog("Актуализация остановлена пользователем.")
        statusText = "Актуализация остановлена"
    }

    private func onActualizationError(_ message: String) {
        appendLog("Ошибка: \(message)")
        statusText = "Ошибка актуализации"
        Dialogs.error("Ошибка актуализации", message)
    }

    // MARK: - Экспорт

    func exportCatalog() {
        let state = currentState
        let site = currentSite
        if state.products.isEmpty {
            Dialogs.info("Каталог пуст", "Нечего экспортировать — каталог пуст.")
            return
        }
        guard let path = Dialogs.saveTextFile(title: "Экспорт каталога", defaultName: "\(site.key)_catalog_export.txt") else {
            return
        }
        let ordered = state.products.sorted {
            CatalogText.normalizeTitle($0.title) < CatalogText.normalizeTitle($1.title)
        }
        do {
            try CatalogText.serializeCatalog(ordered, header: state.header)
                .write(to: path, atomically: true, encoding: .utf8)
        } catch {
            Dialogs.error("Ошибка экспорта", error.localizedDescription)
            return
        }
        exportSuccessName = path.lastPathComponent
        statusText = "Экспортировано \(ordered.count) товаров"
    }

    // MARK: - Закрытие окна

    /// Возвращает true, если окно можно закрыть.
    func confirmClose() -> Bool {
        if isRunning {
            let ok = Dialogs.confirm(
                "Актуализация выполняется",
                "Актуализация ещё выполняется. Прервать и закрыть приложение?"
            )
            if !ok { return false }
            cancelFlag.set()
        }
        let dirty = dirtySiteLabels()
        if !dirty.isEmpty {
            let ok = Dialogs.confirm(
                "Несохранённые изменения",
                "Есть несохранённые изменения в каталоге: " + dirty.joined(separator: ", ") + ". Закрыть без сохранения?"
            )
            if !ok { return false }
        }
        return true
    }
}
