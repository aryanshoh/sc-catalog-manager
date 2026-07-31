import SwiftUI

// Корневая раскладка окна: тулбар (заголовок + Открыть/Сохранить), sidebar,
// область раздела и статус-бар. Оконный хром — нативный (безрамочность даёт
// .hiddenTitleBar), поэтому кастомные «светофоры» из Qt-версии не нужны.

struct ContentView: View {
    @ObservedObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            HStack(spacing: 0) {
                SidebarView(app: app)
                content
            }
            statusBar
        }
        .background(Theme.backgroundShape)
        .preferredColorScheme(app.themeID.palette.colorScheme)
        .sheet(item: $app.orphanSheet) { context in
            OrphanSheetView(context: context) { toRemove in
                app.applyOrphanDecision(context: context, toRemove: toRemove)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch app.activeSection {
        case .menu: MenuPageView(app: app)
        case .actualize: ActualizePageView(app: app)
        case .export: ExportPageView(app: app)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            // Место под нативные «светофоры» слева.
            Spacer().frame(width: 68)
            Spacer()
            HStack(spacing: 6) {
                Text("Catalog Manager — \(app.currentSite.shortLabel)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.n(200))
                if app.currentState.dirty {
                    Circle().fill(Theme.accent).frame(width: 6, height: 6)
                }
            }
            Spacer()
            NocturneButton(title: "Open", systemImage: "folder", kind: .ghost) { app.openCatalog() }
            NocturneButton(title: "Save", systemImage: "square.and.arrow.down", kind: .secondary) { app.saveCatalog() }
        }
        .padding(.horizontal, 16)
        .frame(height: Theme.toolbarHeight)
        .background(Theme.n(900))
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.n(800)).frame(height: 1) }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
                .foregroundColor(Theme.n(300))
            Text(app.statusText)
                .font(.system(size: 11.5))
                .foregroundColor(Theme.n(300))
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: Theme.statusbarHeight)
        .background(Theme.n(900))
        .overlay(alignment: .top) { Rectangle().fill(Theme.n(800)).frame(height: 1) }
    }
}
