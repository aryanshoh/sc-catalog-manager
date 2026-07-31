import SwiftUI

// Раздел «Экспорт»: кнопка экспорта в txt и предпросмотр каталога по алфавиту
// (порт ExportPage). На iOS сохранение файла идёт через системный экспортёр.

struct ExportView: View {
    @ObservedObject var app: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Экспортирует все товары текущего каталога вместе с описаниями в один txt-файл, отсортированный по названию.")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.n(300))
                        .fixedSize(horizontal: false, vertical: true)

                    NocturneButton(title: "Экспортировать в TXT…", systemImage: "square.and.arrow.up", kind: .primary) {
                        app.exportCatalog()
                    }

                    if let name = app.exportSuccessName {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.a(200))
                            Text("\(name) сохранён")
                                .font(.system(size: 13))
                                .foregroundColor(Theme.a(100))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Theme.a(800))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
                    }

                    SectionCaption(text: "ПРЕДПРОСМОТР · ПО АЛФАВИТУ")
                    previewCard
                }
                .padding(20)
            }
            .background(ThemedBackground(theme: app.themeID))
            .navigationTitle("Экспорт")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var previewCard: some View {
        let ordered = app.currentState.products.sorted {
            CatalogText.normalizeTitle($0.title) < CatalogText.normalizeTitle($1.title)
        }
        return VStack(alignment: .leading, spacing: 0) {
            if ordered.isEmpty {
                Text("Каталог пуст.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.n(400))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 16)
            } else {
                ForEach(Array(ordered.enumerated()), id: \.offset) { index, product in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(product.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Theme.n(100))
                        if let short = shortDesc(product) {
                            Text(short)
                                .font(.system(size: 13))
                                .foregroundColor(Theme.n(300))
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    if index < ordered.count - 1 {
                        Rectangle().fill(Theme.n(800)).frame(height: 1)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.n(900))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLG).stroke(Theme.n(800), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLG))
    }

    private func shortDesc(_ product: Product) -> String? {
        let s = (product.sections["Краткое описание"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
