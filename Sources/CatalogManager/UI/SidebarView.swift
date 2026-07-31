import SwiftUI

// Левый sidebar: выбор сайта, разделы приложения и футер с именем файла и
// количеством продуктов. Порт класса Sidebar из catalog_app_qt.py.

struct SidebarRow: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundColor(isActive ? Theme.a(100) : Theme.n(200))
                    .frame(width: 16)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundColor(isActive ? Theme.a(100) : Theme.n(200))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
            .overlay {
                if isActive, let stroke = Theme.fillStroke {
                    RoundedRectangle(cornerRadius: Theme.radiusSM).stroke(stroke, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var background: Color {
        if isActive { return Theme.a(800) }
        return hovering ? Theme.n(800) : .clear
    }
}

struct SidebarView: View {
    @ObservedObject var app: AppState

    private static let sectionRows: [(AppState.Section, String, String)] = [
        (.menu, "Product menu", "square.grid.2x2"),
        (.actualize, "Catalog update", "arrow.clockwise"),
        (.export, "Export", "square.and.arrow.up"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionCaption(text: "SITE").padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
            ForEach(Sites.all) { site in
                SidebarRow(
                    title: site.shortLabel,
                    systemImage: "storefront",
                    isActive: site.key == app.activeSiteKey
                ) { app.switchSite(site.key) }
                .disabled(app.isRunning && site.key != app.activeSiteKey)
                .opacity(app.isRunning && site.key != app.activeSiteKey ? 0.5 : 1)
            }

            SectionCaption(text: "SECTIONS").padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 2)
            ForEach(Self.sectionRows, id: \.0) { section, label, icon in
                SidebarRow(
                    title: label,
                    systemImage: icon,
                    isActive: section == app.activeSection
                ) { app.switchSection(section) }
            }

            SectionCaption(text: "APPEARANCE").padding(.horizontal, 8).padding(.top, 14).padding(.bottom, 2)
            ForEach(ThemeID.allCases) { theme in
                SidebarRow(
                    title: theme.title,
                    systemImage: theme.icon,
                    isActive: theme == app.themeID
                ) { app.setTheme(theme) }
            }

            Spacer(minLength: 0)
            footer
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .frame(width: Theme.sidebarWidth)
        .background(Theme.n(900))
        .overlay(alignment: .trailing) {
            Rectangle().fill(Theme.n(800)).frame(width: 1)
        }
    }

    private var footer: some View {
        let state = app.currentState
        let name = state.path?.lastPathComponent ?? "new catalog (not saved)"
        let suffix = state.dirty ? " · unsaved" : " · saved"
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.n(400))
                Text(name)
                    .font(.system(size: 11.5))
                    .foregroundColor(Theme.n(300))
                    .lineLimit(2)
            }
            Text("\(state.products.count) products\(suffix)")
                .font(.system(size: 11.5))
                .foregroundColor(Theme.n(400))
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.n(800)).frame(height: 1)
        }
        .padding(.bottom, 8)
    }
}
