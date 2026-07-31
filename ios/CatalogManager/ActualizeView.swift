import SwiftUI

// Раздел «Актуализация каталога»: запуск/остановка сверки, прогресс, карточки
// статистики и журнал. На iPhone карточки статистики раскладываются сеткой 2×N,
// а не в один ряд (порт ActualizePage).

struct StatCard: View {
    let value: Int
    let label: String
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(value)")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(accent ? Theme.a(200) : Theme.n(100))
            Text(label)
                .font(.system(size: 12.5))
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

struct ActualizeView: View {
    @ObservedObject var app: AppState

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    subtitle

                    VStack(spacing: 10) {
                        NocturneButton(
                            title: "Surface", systemImage: "magnifyingglass",
                            kind: .primary, isEnabled: !app.isRunning
                        ) { Task { await app.startActualization(mode: .surface) } }

                        NocturneButton(
                            title: "Full", systemImage: "arrow.clockwise",
                            kind: .secondary, isEnabled: !app.isRunning
                        ) { Task { await app.startActualization(mode: .full) } }

                        if app.isRunning {
                            NocturneButton(title: "Stop", kind: .ghost, isEnabled: true) {
                                app.cancelActualization()
                            }
                        }
                    }

                    if app.progressTotal > 0 || app.isRunning {
                        HStack {
                            ProgressView(value: progressFraction)
                                .tint(Theme.accent)
                            if app.progressTotal > 0 {
                                Text("\(app.progressCurrent) / \(app.progressTotal)")
                                    .font(.system(size: 13))
                                    .foregroundColor(Theme.n(300))
                                    .monospacedDigit()
                            }
                        }
                    }

                    if app.showStats, let result = app.lastResult {
                        LazyVGrid(columns: columns, spacing: 10) {
                            StatCard(value: result.added.count, label: "Added", accent: true)
                            StatCard(value: result.updated.count, label: "Updated", accent: true)
                            StatCard(value: result.unchanged.count, label: "No changes")
                            StatCard(value: result.orphans.count, label: "Not on site")
                            StatCard(value: result.failed.count, label: "Errors")
                        }
                    }

                    SectionCaption(text: "LOG")
                    logPanel
                }
                .padding(20)
            }
            .background(ThemedBackground(theme: app.themeID))
            .navigationTitle("Update")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var progressFraction: Double {
        app.progressTotal > 0 ? Double(app.progressCurrent) / Double(app.progressTotal) : 0
    }

    private var subtitle: some View {
        let site = app.currentSite
        let line1 = Text("Compares the catalog with the site ").foregroundColor(Theme.n(300))
            + Text(site.shopURL).foregroundColor(Theme.accent)
            + Text(".").foregroundColor(Theme.n(300))
        let line2 = Text("Surface").foregroundColor(Theme.a(300))
            + Text(" — quickly adds only new products (matches by name, doesn't touch existing descriptions).").foregroundColor(Theme.n(300))
        let line3 = Text("Full").foregroundColor(Theme.a(300))
            + Text(" — opens every product page, updates changed descriptions, and finds products no longer on the site.").foregroundColor(Theme.n(300))
        return VStack(alignment: .leading, spacing: 6) {
            line1
            line2
            line3
        }
        .font(.system(size: 14))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var logPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(app.logText.isEmpty ? "The log will appear here after the update starts…" : app.logText)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundColor(app.logText.isEmpty ? Theme.n(500) : Theme.n(200))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .id("logBottom")
            }
            .onChange(of: app.logText) { _, _ in
                withAnimation { proxy.scrollTo("logBottom", anchor: .bottom) }
            }
        }
        .frame(height: 260)
        .background(Theme.n(900))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMD).stroke(Theme.n(800), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD))
    }
}
