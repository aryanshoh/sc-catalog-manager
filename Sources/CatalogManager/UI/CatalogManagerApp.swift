import SwiftUI
import AppKit
import Sparkle

// Точка входа приложения. Нативное безрамочное окно (.hiddenTitleBar) с тёмной
// темой; подтверждение закрытия при несохранённых изменениях/идущей
// актуализации — через NSWindowDelegate.windowShouldClose (аналог closeEvent).

@main
struct CatalogManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var app = AppState.shared

    // Контроллер авто-обновления Sparkle. Feed-URL и публичный ключ берутся из
    // Info.plist (SUFeedURL / SUPublicEDKey), которые проставляет build_app.sh.
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView(app: app)
                .frame(minWidth: 880, minHeight: 600)
                .frame(idealWidth: 1220, idealHeight: 780)
                .background(WindowConfigurator())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Открыть…") { app.openCatalog() }
                    .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Сохранить") { app.saveCatalog() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("Сохранить как…") { app.saveCatalogAs() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }
            // Пункт «Проверить обновления…» в меню приложения (рядом с «О программе»).
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

/// Кнопка «Проверить обновления…», которая сама выключается, пока проверка
/// невозможна (идёт другая проверка/не сконфигурировано). Стандартный паттерн
/// Sparkle для SwiftUI.
struct CheckForUpdatesView: View {
    @ObservedObject private var checker: UpdaterCheckability
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        self.checker = UpdaterCheckability(updater: updater)
    }

    var body: some View {
        Button("Проверить обновления…") { updater.checkForUpdates() }
            .disabled(!checker.canCheckForUpdates)
    }
}

/// Публикует свойство updater.canCheckForUpdates как @Published для SwiftUI.
final class UpdaterCheckability: ObservableObject {
    @Published var canCheckForUpdates = false
    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static private(set) var shared: AppDelegate?

    override init() {
        super.init()
        AppDelegate.shared = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // Аналог closeEvent: гейтим закрытие окна подтверждением.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated {
            AppState.shared.confirmClose()
        }
    }
}

/// Настраивает NSWindow, в которое встроена SwiftUI-иерархия: прозрачный
/// титул-бар, перетаскивание за фон, тёмный вид и делегат закрытия.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            // Фон окна берём из текущей палитры; системную схему (свет/тьма)
            // задаёт .preferredColorScheme у корневого view.
            window.backgroundColor = Theme.current.windowBackground
            if let delegate = AppDelegate.shared {
                window.delegate = delegate
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
