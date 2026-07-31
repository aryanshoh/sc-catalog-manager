import Foundation

// Механизм актуализации. Два режима:
//   .full    — полная: заходит в каждую карточку, сверяет названия И описания,
//              обновляет изменившееся, находит «сирот» (порт actualize_catalog).
//   .surface — поверхностная: сверяет только по названиям из списка магазина,
//              заходит в карточку и качает описание лишь для НОВЫХ товаров.
//              Ничего не обновляет и не ищет «сирот» — быстро добавляет новинки.

enum ActualizationMode {
    case surface
    case full
}

func actualizeCatalog(
    mode: ActualizationMode,
    localProducts: [Product],
    scraper: Scraper,
    site: Site,
    log: @Sendable (String) -> Void,
    cancel: CancelFlag,
    progress: (@Sendable (Int, Int) -> Void)? = nil
) async throws -> ActualizationResult {
    switch mode {
    case .full:
        return try await actualizeFull(localProducts, scraper: scraper, site: site, log: log, cancel: cancel, progress: progress)
    case .surface:
        return try await actualizeSurface(localProducts, scraper: scraper, site: site, log: log, cancel: cancel, progress: progress)
    }
}

// MARK: - Полная актуализация

private func actualizeFull(
    _ localProducts: [Product],
    scraper: Scraper,
    site: Site,
    log: @Sendable (String) -> Void,
    cancel: CancelFlag,
    progress: (@Sendable (Int, Int) -> Void)?
) async throws -> ActualizationResult {
    var resultCatalog = localProducts
    var indexByNorm: [String: Int] = [:]
    for (i, product) in localProducts.enumerated() {
        indexByNorm[CatalogText.normalizeTitle(product.title)] = i
    }
    var seenNormTitles = Set<String>()

    var added: [String] = []
    var updated: [String] = []
    var unchanged: [String] = []
    var failed: [(url: String, error: String)] = []

    log("Полная актуализация. Собираю ссылки на товары (\(site.label))…")
    let links = try await scraper.collectProductLinks(shopURL: site.shopURL, log: log, cancel: cancel)
    let total = links.count
    log("Всего товаров на сайте: \(total)")

    for (offset, url) in links.enumerated() {
        let i = offset + 1
        if cancel.isSet { throw CancelledError() }

        let scraped: Product
        do {
            scraped = try await scraper.callWithReconnect("товар \(i)/\(total)", log: log, cancel: cancel) {
                try await scraper.fetchProduct(url, titleSuffixPattern: site.titleSuffixPattern)
            }
        } catch is CancelledError {
            throw CancelledError()
        } catch {
            let message = errorMessage(error)
            failed.append((url: url, error: message))
            log("[\(i)/\(total)] Ошибка загрузки \(url): \(message)")
            progress?(i, total)
            try await Scraper.humanPacingSleep(cancel: cancel)
            continue
        }

        let normTitle = CatalogText.normalizeTitle(scraped.title)
        seenNormTitles.insert(normTitle)

        if let idx = indexByNorm[normTitle] {
            let localProduct = resultCatalog[idx]
            if localProduct.signature() != scraped.signature() {
                resultCatalog[idx] = scraped
                updated.append(scraped.title)
                log("[\(i)/\(total)] Обновлено: \(scraped.title)")
            } else {
                // Содержание не изменилось, но дату публикации подтягиваем со
                // свежей страницы и для «неизменившихся»: в signature() она не
                // входит, поэтому это не считается обновлением, но дата
                // появляется и у ранее сохранённых товаров без неё.
                let scrapedDate = scraped.sections[CoreConstants.publishDateSection]
                if let scrapedDate, !scrapedDate.isEmpty,
                   localProduct.sections[CoreConstants.publishDateSection] != scrapedDate {
                    localProduct.sections[CoreConstants.publishDateSection] = scrapedDate
                }
                unchanged.append(scraped.title)
                log("[\(i)/\(total)] Без изменений: \(scraped.title)")
            }
        } else {
            resultCatalog.append(scraped)
            indexByNorm[normTitle] = resultCatalog.count - 1
            added.append(scraped.title)
            log("[\(i)/\(total)] Добавлено: \(scraped.title)")
        }

        progress?(i, total)
        try await Scraper.humanPacingSleep(cancel: cancel)
    }

    let orphans = localProducts.filter { !seenNormTitles.contains(CatalogText.normalizeTitle($0.title)) }

    return ActualizationResult(
        catalog: resultCatalog,
        added: added, updated: updated, unchanged: unchanged,
        orphans: orphans, failed: failed
    )
}

// MARK: - Поверхностная актуализация

private func actualizeSurface(
    _ localProducts: [Product],
    scraper: Scraper,
    site: Site,
    log: @Sendable (String) -> Void,
    cancel: CancelFlag,
    progress: (@Sendable (Int, Int) -> Void)?
) async throws -> ActualizationResult {
    var resultCatalog = localProducts
    var existing = Set(localProducts.map { CatalogText.normalizeTitle($0.title) })

    var added: [String] = []
    var unchanged: [String] = []   // уже есть в каталоге
    var failed: [(url: String, error: String)] = []

    log("Поверхностная актуализация. Собираю названия товаров со страниц магазина (\(site.label))…")
    let entries = try await scraper.collectProductEntries(shopURL: site.shopURL, log: log, cancel: cancel)
    let total = entries.count
    log("Всего товаров на сайте: \(total)")

    for (offset, entry) in entries.enumerated() {
        let i = offset + 1
        if cancel.isSet { throw CancelledError() }

        // Если название удалось прочитать из списка и оно уже есть — пропускаем
        // без захода в карточку (главная экономия поверхностного режима).
        if let title = entry.title, existing.contains(CatalogText.normalizeTitle(title)) {
            unchanged.append(title)
            log("[\(i)/\(total)] Уже в каталоге: \(title)")
            progress?(i, total)
            continue
        }

        // Новый (или название из списка не прочиталось) — заходим в карточку.
        let scraped: Product
        do {
            scraped = try await scraper.callWithReconnect("товар \(i)/\(total)", log: log, cancel: cancel) {
                try await scraper.fetchProduct(entry.url, titleSuffixPattern: site.titleSuffixPattern)
            }
        } catch is CancelledError {
            throw CancelledError()
        } catch {
            let message = errorMessage(error)
            failed.append((url: entry.url, error: message))
            log("[\(i)/\(total)] Ошибка загрузки \(entry.url): \(message)")
            progress?(i, total)
            try await Scraper.humanPacingSleep(cancel: cancel)
            continue
        }

        let normTitle = CatalogText.normalizeTitle(scraped.title)
        if existing.contains(normTitle) {
            unchanged.append(scraped.title)
            log("[\(i)/\(total)] Уже в каталоге: \(scraped.title)")
        } else {
            resultCatalog.append(scraped)
            existing.insert(normTitle)
            added.append(scraped.title)
            log("[\(i)/\(total)] Добавлено: \(scraped.title)")
        }

        progress?(i, total)
        try await Scraper.humanPacingSleep(cancel: cancel)
    }

    // Поверхностный режим только добавляет новинки: без обновлений и «сирот».
    return ActualizationResult(
        catalog: resultCatalog,
        added: added, updated: [], unchanged: unchanged,
        orphans: [], failed: failed
    )
}

private func errorMessage(_ error: Error) -> String {
    if let localized = error as? LocalizedError, let description = localized.errorDescription {
        return description
    }
    return error.localizedDescription
}
