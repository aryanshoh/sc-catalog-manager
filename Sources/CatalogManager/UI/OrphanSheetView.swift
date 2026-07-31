import SwiftUI

// Модальный sheet «Товары, отсутствующие на сайте»: пользователь отмечает,
// какие «сироты» оставить. Порт класса OrphanSheet.

struct OrphanSheetView: View {
    let context: AppState.OrphanContext
    let onApply: ([Product]) -> Void

    @State private var keep: [ObjectIdentifier: Bool] = [:]

    private var orphans: [Product] {
        context.orphans.sorted {
            CatalogText.normalizeTitle($0.title) < CatalogText.normalizeTitle($1.title)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.n(800))
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(orphans) { product in
                        row(product)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 360)
            footer
        }
        .frame(width: 560)
        .background(Theme.n(900))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusLG))
        .onAppear {
            for product in context.orphans where keep[product.id] == nil {
                keep[product.id] = true
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 18))
                    .foregroundColor(Theme.a(300))
                Text("Products missing on the site")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Theme.n(100))
                Spacer()
            }
            Text("\(context.orphans.count) product(s) from the local catalog were not found on the site. Check the ones to keep — unchecked ones will be removed after “Apply”.")
                .font(.system(size: 12.5))
                .foregroundColor(Theme.n(300))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                NocturneButton(title: "Keep all", kind: .ghost) { setAll(true) }
                NocturneButton(title: "Remove all", kind: .ghost) { setAll(false) }
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 16)
    }

    private func row(_ product: Product) -> some View {
        let isKept = keep[product.id] ?? true
        return HStack {
            Toggle(isOn: Binding(
                get: { keep[product.id] ?? true },
                set: { keep[product.id] = $0 }
            )) {
                Text(product.title)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.n(100))
            }
            .toggleStyle(.checkbox)
            Spacer()
            Text(isKept ? "keep" : "will be removed")
                .font(.system(size: 11.5))
                .foregroundColor(isKept ? Theme.a(300) : Theme.n(400))
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            NocturneButton(title: "Apply", kind: .primary) {
                let toRemove = context.orphans.filter { !(keep[$0.id] ?? true) }
                onApply(toRemove)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(Theme.bg)
        .overlay(alignment: .top) { Rectangle().fill(Theme.n(800)).frame(height: 1) }
    }

    private func setAll(_ value: Bool) {
        for product in context.orphans {
            keep[product.id] = value
        }
    }
}
