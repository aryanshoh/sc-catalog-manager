import SwiftUI
import UniformTypeIdentifiers

// Корневой экран: нижний TabView с четырьмя разделами. Здесь же централизованно
// подключены общие для всего приложения представления — документ-пикер открытия,
// экспортёр, sheet «сироты» и хост асинхронных алертов.

struct RootView: View {
    @ObservedObject var app: AppState

    var body: some View {
        TabView {
            MenuView(app: app)
                .tabItem { Label("Catalog", systemImage: "square.grid.2x2") }

            ActualizeView(app: app)
                .tabItem { Label("Update", systemImage: "arrow.clockwise") }

            ExportView(app: app)
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }

            SettingsView(app: app)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.accent)
        // Открытие каталога (аналог NSOpenPanel)
        .fileImporter(
            isPresented: $app.fileImporterPresented,
            allowedContentTypes: [.plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            app.handlePickedCatalog(result)
        }
        // Сохранить как… / Экспорт (аналог NSSavePanel)
        .fileExporter(
            isPresented: $app.exporterPresented,
            document: app.exportDocument,
            contentType: .plainText,
            defaultFilename: app.exportFilename
        ) { result in
            app.handleExportResult(result)
        }
        // Модальный лист «Товары, отсутствующие на сайте»
        .sheet(item: $app.orphanSheet) { context in
            OrphanView(context: context, themeID: app.themeID) { toRemove in
                Task { await app.applyOrphanDecision(context: context, toRemove: toRemove) }
            }
        }
        .dialogHost(app.dialogs)
    }
}
