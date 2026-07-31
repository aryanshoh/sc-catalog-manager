import SwiftUI

// Раздел «Экспорт»: кнопка экспорта в txt и предпросмотр каталога по алфавиту.
// Порт класса ExportPage.

struct ExportPageView: View {
    @ObservedObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Экспорт каталога")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Theme.n(100))

            Text("Экспортирует все товары текущего каталога вместе с их описаниями в один txt-файл, отсортированный по названию.")
                .font(.system(size: 13))
                .foregroundColor(Theme.n(300))
                .frame(maxWidth: 640, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                NocturneButton(title: "Экспортировать в TXT…", systemImage: "square.and.arrow.up", kind: .primary) {
                    app.exportCatalog()
                }
                if let name = app.exportSuccessName {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.a(100))
                        Text("\(name) сохранён")
                            .font(.system(size: 11.5))
                            .foregroundColor(Theme.a(100))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Theme.a(800))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
                }
                Spacer()
            }

            previewCard
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var previewCard: some View {
        let ordered = app.currentState.products.sorted {
            CatalogText.normalizeTitle($0.title) < CatalogText.normalizeTitle($1.title)
        }
        return VStack(alignment: .leading, spacing: 10) {
            SectionCaption(text: "ПРЕДПРОСМОТР · ПО АЛФАВИТУ")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(ordered.enumerated()), id: \.offset) { index, product in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(product.title)
                                .font(.system(size: 13.5, weight: .medium))
                                .foregroundColor(Theme.n(100))
                            if let short = shortDesc(product) {
                                Text(short)
                                    .font(.system(size: 12))
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
            .frame(maxHeight: 380)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Theme.n(900))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusLG).stroke(Theme.n(800), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLG))
    }

    private func shortDesc(_ product: Product) -> String? {
        let s = (product.sections["Краткое описание"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }
}
