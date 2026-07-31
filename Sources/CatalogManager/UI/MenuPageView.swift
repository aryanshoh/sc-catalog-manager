import SwiftUI

// Раздел «Меню продуктов»: слева — поиск и дерево категорий/товаров, справа —
// подробности выбранного товара. Порт класса MenuPage.

struct MenuPageView: View {
    @ObservedObject var app: AppState

    var body: some View {
        HStack(spacing: 0) {
            outline
                .frame(width: Theme.outlineWidth)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Theme.n(800)).frame(width: 1)
                }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Outline

    private var outline: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.n(400))
                TextField("Поиск по названию", text: $app.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundColor(Theme.n(100))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.n(800))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.fillStroke ?? Theme.n(700), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(12)

            Rectangle().fill(Theme.n(800)).frame(height: 1)

            if !app.menuGroups().isEmpty {
                HStack(spacing: 6) {
                    OutlineToolButton(title: "Развернуть все", systemImage: "rectangle.expand.vertical") {
                        app.expandAllCategories()
                    }
                    OutlineToolButton(title: "Свернуть все", systemImage: "rectangle.compress.vertical") {
                        app.collapseAllCategories()
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Rectangle().fill(Theme.n(800)).frame(height: 1)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(app.menuGroups(), id: \.category) { group in
                        categoryDisclosure(group.category, group.products)
                    }
                }
                .padding(8)
            }
        }
    }

    private func categoryDisclosure(_ name: String, _ products: [Product]) -> some View {
        let expanded = !app.collapsedCategories.contains(name)
        return VStack(alignment: .leading, spacing: 2) {
            Button {
                if expanded { app.collapsedCategories.insert(name) }
                else { app.collapsedCategories.remove(name) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.n(300))
                        .frame(width: 12)
                    Text("\(name)   \(products.count)")
                        .font(.system(size: 12.5))
                        .foregroundColor(Theme.n(200))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                ForEach(products) { product in
                    productRow(product)
                }
            }
        }
    }

    private func productRow(_ product: Product) -> some View {
        let isSelected = app.selectedProduct === product
        return Button {
            app.selectedProduct = product
        } label: {
            Text(product.title)
                .font(.system(size: 12.5))
                .foregroundColor(isSelected ? Theme.a(100) : Theme.n(200))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.leading, 18)
                .padding(.trailing, 4)
                .background(isSelected ? Theme.a(800) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
                .overlay {
                    if isSelected, let stroke = Theme.fillStroke {
                        RoundedRectangle(cornerRadius: Theme.radiusSM).stroke(stroke, lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let product = app.selectedProduct {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(product.title)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundColor(Theme.n(100))
                        .frame(maxWidth: 620, alignment: .leading)

                    chips(product)

                    if let short = trimmed(product.sections["Краткое описание"]) {
                        SectionCaption(text: "КРАТКОЕ ОПИСАНИЕ", color: Theme.a(300))
                        Text(short)
                            .font(.system(size: 13.5))
                            .foregroundColor(Theme.n(100))
                            .lineSpacing(4)
                            .frame(maxWidth: 620, alignment: .leading)
                            .textSelection(.enabled)
                    }

                    if let full = trimmed(product.sections["Полное описание"]) {
                        SectionCaption(text: "ПОЛНОЕ ОПИСАНИЕ", color: Theme.a(300))
                        Text(full)
                            .font(.system(size: 13))
                            .foregroundColor(Theme.n(200))
                            .lineSpacing(5)
                            .frame(maxWidth: 620, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: 40))
                    .foregroundColor(Theme.n(400))
                Text("Выберите продукт в списке слева")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.n(400))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func chips(_ product: Product) -> some View {
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
        .frame(maxWidth: 620, alignment: .leading)
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
