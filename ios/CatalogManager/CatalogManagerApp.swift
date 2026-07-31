import SwiftUI

// Точка входа iOS-приложения. Вместо безрамочного окна macOS — стандартная
// сцена с корневым TabView (нижняя навигация — нативный для iPhone паттерн).

@main
struct CatalogManagerApp: App {
    @StateObject private var app = AppState.shared

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
                .preferredColorScheme(app.themeID.palette.colorScheme)
        }
    }
}
