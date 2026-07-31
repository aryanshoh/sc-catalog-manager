import SwiftUI

// Раздел «Настройки»: то, что в macOS-версии жило в sidebar — выбор сайта,
// оформление — плюс сведения о текущем файле и файловые операции. Нижней
// навигации iPhone привычнее держать это на отдельной вкладке.

struct SettingsView: View {
    @ObservedObject var app: AppState

    var body: some View {
        NavigationStack {
            List {
                siteSection
                fileSection
                themeSection
                statusSection
            }
            .scrollContentBackground(.hidden)
            .background(ThemedBackground(theme: app.themeID))
            .navigationTitle("Настройки")
        }
    }

    private var siteSection: some View {
        Section {
            ForEach(Sites.all) { site in
                Button {
                    app.switchSite(site.key)
                } label: {
                    HStack {
                        Image(systemName: "storefront")
                            .foregroundColor(Theme.n(300)).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(site.shortLabel).foregroundColor(Theme.n(100))
                            Text(site.shopURL).font(.system(size: 12)).foregroundColor(Theme.n(400))
                        }
                        Spacer()
                        if site.key == app.activeSiteKey {
                            Image(systemName: "checkmark").foregroundColor(Theme.accent)
                        }
                    }
                }
                .disabled(app.isRunning && site.key != app.activeSiteKey)
                .listRowBackground(Theme.n(900))
            }
        } header: {
            Text("Сайт").foregroundColor(Theme.n(400))
        } footer: {
            if app.isRunning {
                Text("Во время актуализации переключение сайта недоступно.")
                    .foregroundColor(Theme.n(400))
            }
        }
    }

    private var fileSection: some View {
        Section {
            let state = app.currentState
            HStack {
                Image(systemName: "doc.text").foregroundColor(Theme.n(300)).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.path?.lastPathComponent ?? "новый каталог (не сохранён)")
                        .foregroundColor(Theme.n(100)).lineLimit(2)
                    Text("\(state.products.count) продуктов · \(state.dirty ? "не сохранено" : "сохранено")")
                        .font(.system(size: 12)).foregroundColor(Theme.n(400))
                }
            }
            .listRowBackground(Theme.n(900))

            Button {
                Task { await app.requestOpenCatalog() }
            } label: {
                Label("Открыть каталог…", systemImage: "folder").foregroundColor(Theme.n(100))
            }
            .listRowBackground(Theme.n(900))

            Button {
                Task { await app.saveCatalog() }
            } label: {
                Label("Сохранить", systemImage: "square.and.arrow.down").foregroundColor(Theme.n(100))
            }
            .disabled(app.currentState.products.isEmpty)
            .listRowBackground(Theme.n(900))

            Button {
                app.saveCatalogAs()
            } label: {
                Label("Сохранить как…", systemImage: "square.and.arrow.down.on.square").foregroundColor(Theme.n(100))
            }
            .disabled(app.currentState.products.isEmpty)
            .listRowBackground(Theme.n(900))
        } header: {
            Text("Файл").foregroundColor(Theme.n(400))
        }
    }

    private var themeSection: some View {
        Section {
            ForEach(ThemeID.allCases) { theme in
                Button {
                    app.setTheme(theme)
                } label: {
                    HStack {
                        Image(systemName: theme.icon).foregroundColor(Theme.n(300)).frame(width: 22)
                        Text(theme.title).foregroundColor(Theme.n(100))
                        Spacer()
                        if theme == app.themeID {
                            Image(systemName: "checkmark").foregroundColor(Theme.accent)
                        }
                    }
                }
                .listRowBackground(Theme.n(900))
            }
        } header: {
            Text("Оформление").foregroundColor(Theme.n(400))
        }
    }

    private var statusSection: some View {
        Section {
            Text(app.statusText)
                .font(.system(size: 13))
                .foregroundColor(Theme.n(300))
                .listRowBackground(Theme.n(900))
        } header: {
            Text("Статус").foregroundColor(Theme.n(400))
        }
    }
}
