import SwiftUI

// Модальный лист «Товары, отсутствующие на сайте»: пользователь отмечает, какие
// «сироты» оставить. На iOS — sheet с NavigationStack, чекбоксы-переключатели
// (Toggle) и кнопка «Применить» в навбаре (порт OrphanSheet).

struct OrphanView: View {
    let context: AppState.OrphanContext
    var themeID: ThemeID = .dark
    let onApply: ([Product]) -> Void

    @State private var keep: [ObjectIdentifier: Bool] = [:]
    @Environment(\.dismiss) private var dismiss

    private var orphans: [Product] {
        context.orphans.sorted {
            CatalogText.normalizeTitle($0.title) < CatalogText.normalizeTitle($1.title)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(orphans) { product in
                        row(product)
                    }
                } header: {
                    Text("\(context.orphans.count) product(s) were not found on the site. Check the ones to keep — unchecked ones will be removed after “Apply”.")
                        .textCase(nil)
                        .font(.system(size: 13))
                        .foregroundColor(Theme.n(300))
                }
            }
            .scrollContentBackground(.hidden)
            .background(ThemedBackground(theme: themeID))
            .navigationTitle("Missing on the site")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu("All") {
                        Button("Keep all") { setAll(true) }
                        Button("Remove all") { setAll(false) }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Apply") {
                        let toRemove = context.orphans.filter { !(keep[$0.id] ?? true) }
                        onApply(toRemove)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            for product in context.orphans where keep[product.id] == nil {
                keep[product.id] = true
            }
        }
    }

    private func row(_ product: Product) -> some View {
        let isKept = keep[product.id] ?? true
        return Toggle(isOn: Binding(
            get: { keep[product.id] ?? true },
            set: { keep[product.id] = $0 }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.title)
                    .font(.system(size: 15))
                    .foregroundColor(Theme.n(100))
                Text(isKept ? "will be kept" : "will be removed")
                    .font(.system(size: 12))
                    .foregroundColor(isKept ? Theme.a(300) : Theme.n(400))
            }
        }
        .tint(Theme.accent)
        .listRowBackground(Theme.n(900))
    }

    private func setAll(_ value: Bool) {
        for product in context.orphans {
            keep[product.id] = value
        }
    }
}
