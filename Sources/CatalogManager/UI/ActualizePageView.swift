import SwiftUI

// Раздел «Актуализация каталога»: запуск/остановка сверки, прогресс,
// карточки статистики и журнал. Порт класса ActualizePage.

struct StatCard: View {
    let value: Int
    let label: String
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(accent ? Theme.a(200) : Theme.n(100))
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(Theme.n(300))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.n(900))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMD).stroke(Theme.n(800), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD))
    }
}

struct ActualizePageView: View {
    @ObservedObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Актуализация каталога")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(Theme.n(100))

            subtitle

            HStack(spacing: 8) {
                NocturneButton(
                    title: "Поверхностная", systemImage: "magnifyingglass",
                    kind: .primary, isEnabled: !app.isRunning
                ) { app.startActualization(mode: .surface) }
                NocturneButton(
                    title: "Полная", systemImage: "arrow.clockwise",
                    kind: .secondary, isEnabled: !app.isRunning
                ) { app.startActualization(mode: .full) }
                NocturneButton(title: "Остановить", kind: .ghost, isEnabled: app.isRunning) {
                    app.cancelActualization()
                }
                Spacer()
                if app.progressTotal > 0 {
                    Text("\(app.progressCurrent) / \(app.progressTotal)")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.n(300))
                }
            }

            ProgressView(value: progressFraction)
                .progressViewStyle(.linear)
                .tint(Theme.accent)
                .frame(height: 6)

            if app.showStats, let result = app.lastResult {
                HStack(spacing: 10) {
                    StatCard(value: result.added.count, label: "Добавлено", accent: true)
                    StatCard(value: result.updated.count, label: "Обновлено", accent: true)
                    StatCard(value: result.unchanged.count, label: "Без изменений")
                    StatCard(value: result.orphans.count, label: "Нет на сайте")
                    StatCard(value: result.failed.count, label: "Ошибки")
                }
            }

            SectionCaption(text: "ЖУРНАЛ")

            logPanel
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var progressFraction: Double {
        app.progressTotal > 0 ? Double(app.progressCurrent) / Double(app.progressTotal) : 0
    }

    private var subtitle: some View {
        let site = app.currentSite
        let line1 = Text("Сверяет каталог с сайтом ").foregroundColor(Theme.n(300))
            + Text(site.shopURL).foregroundColor(Theme.accent)
            + Text(".").foregroundColor(Theme.n(300))
        let line2 = Text("Поверхностная").foregroundColor(Theme.a(300))
            + Text(" — быстро добавляет только новые товары (сверка по названию, описания существующих не трогает).").foregroundColor(Theme.n(300))
        let line3 = Text("Полная").foregroundColor(Theme.a(300))
            + Text(" — заходит в каждую карточку, обновляет изменившиеся описания и находит товары, которых больше нет на сайте.").foregroundColor(Theme.n(300))
        return VStack(alignment: .leading, spacing: 6) {
            line1
            line2
            line3
        }
        .font(.system(size: 13))
        .frame(maxWidth: 640, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var logPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(app.logText.isEmpty ? "Журнал появится здесь после запуска актуализации…" : app.logText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(app.logText.isEmpty ? Theme.n(500) : Theme.n(200))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .id("logBottom")
            }
            .onChange(of: app.logText) { _, _ in
                withAnimation { proxy.scrollTo("logBottom", anchor: .bottom) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.n(900))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMD).stroke(Theme.n(800), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD))
    }
}
