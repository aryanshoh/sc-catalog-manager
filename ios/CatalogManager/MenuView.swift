import SwiftUI

// Раздел «Каталог» (порт «Меню продуктов»). На iPhone master-detail из macOS
// превращается в навигацию с push: список категорий/товаров → экран товара.
// Поиск вынесен в системный .searchable; свот-нав по категориям — секции List.

struct MenuView: View {
    @ObservedObject var app: AppState

    var body: some View {
        NavigationStack {
            Group {
                if app.currentState.products.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .background(ThemedBackground(theme: app.themeID))
            .navigationTitle(app.currentSite.shortLabel)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .searchable(text: $app.searchQuery, prompt: "Поиск по названию")
        }
    }

    private var list: some View {
        List {
            ForEach(app.menuGroups(), id: \.category) { group in
                Section {
                    ForEach(group.products) { product in
                        NavigationLink {
                            ProductDetailView(product: product, themeID: app.themeID)
                        } label: {
                            Text(product.title)
                                .font(.system(size: 15))
                                .foregroundColor(Theme.n(100))
                                .lineLimit(2)
                        }
                        .listRowBackground(Theme.n(900))
                    }
                } header: {
                    HStack {
                        Text(group.category).textCase(nil)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.a(300))
                        Spacer()
                        Text("\(group.products.count)")
                            .font(.system(size: 12))
                            .foregroundColor(Theme.n(400))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 44))
                .foregroundColor(Theme.n(400))
            Text("Каталог не открыт")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(Theme.n(200))
            Text("Откройте txt-каталог или запустите актуализацию, чтобы наполнить его.")
                .font(.system(size: 14))
                .foregroundColor(Theme.n(400))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            NocturneButton(title: "Открыть каталог", systemImage: "folder", kind: .primary) {
                Task { await app.requestOpenCatalog() }
            }
            .fixedSize()
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if app.currentState.dirty {
                HStack(spacing: 5) {
                    Circle().fill(Theme.accent).frame(width: 7, height: 7)
                    Text("не сохранено").font(.system(size: 12)).foregroundColor(Theme.n(300))
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    Task { await app.requestOpenCatalog() }
                } label: { Label("Открыть…", systemImage: "folder") }

                Button {
                    Task { await app.saveCatalog() }
                } label: { Label("Сохранить", systemImage: "square.and.arrow.down") }
                .disabled(app.currentState.products.isEmpty)

                Button {
                    app.saveCatalogAs()
                } label: { Label("Сохранить как…", systemImage: "square.and.arrow.down.on.square") }
                .disabled(app.currentState.products.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }
}

// MARK: - Детали товара

struct ProductDetailView: View {
    let product: Product
    let themeID: ThemeID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(product.title)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(Theme.n(100))
                    .textSelection(.enabled)

                chips

                if let date = trimmed(product.sections[CoreConstants.publishDateSection]) {
                    SectionCaption(text: "ДАТА ПУБЛИКАЦИИ", color: Theme.a(300))
                    Text(date)
                        .font(.system(size: 15))
                        .foregroundColor(Theme.n(100))
                        .textSelection(.enabled)
                }

                if let modified = trimmed(product.sections[CoreConstants.modifiedDateSection]) {
                    SectionCaption(text: "ДАТА ИЗМЕНЕНИЯ", color: Theme.a(300))
                    Text(modified)
                        .font(.system(size: 15))
                        .foregroundColor(Theme.n(100))
                        .textSelection(.enabled)
                }

                if let short = trimmed(product.sections["Краткое описание"]) {
                    SectionCaption(text: "КРАТКОЕ ОПИСАНИЕ", color: Theme.a(300))
                    Text(short)
                        .font(.system(size: 15))
                        .foregroundColor(Theme.n(100))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }

                if let full = trimmed(product.sections["Полное описание"]) {
                    SectionCaption(text: "ПОЛНОЕ ОПИСАНИЕ", color: Theme.a(300))
                    Text(full)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.n(200))
                        .lineSpacing(5)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(ThemedBackground(theme: themeID))
        .navigationTitle("Товар")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var chips: some View {
        let categories = product.categories()
        let tags = CatalogText.parseTags(product.sections["Категории и теги"] ?? "")
        return FlowLayout(hSpacing: 6, vSpacing: 6) {
            ForEach(Array(categories.enumerated()), id: \.offset) { _, cat in
                TagChip(text: cat, kind: .accent)
            }
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                TagChip(text: tag, kind: .outline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
