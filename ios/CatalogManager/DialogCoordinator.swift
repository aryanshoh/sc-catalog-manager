import SwiftUI

// На macOS диалоги были модальными синхронными NSAlert'ами, которые «гейтили»
// управляющий поток (вернул true → продолжаем). На iOS алерты декларативные,
// поэтому оборачиваем их в async/await: `await dialogs.confirm(...)` приостанавливает
// вызывающий метод до нажатия кнопки. Внешне логика AppState читается так же
// пошагово, как в оригинале.

@MainActor
final class DialogCoordinator: ObservableObject {
    enum Kind { case confirm, info, error, conflict }

    /// Выбор пользователя в диалоге конфликта записи.
    enum ConflictChoice { case reload, overwrite, cancel }

    struct Request: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let kind: Kind
    }

    @Published var current: Request?

    // Континуация возвращает индекс нажатой кнопки. Смысл индекса зависит от
    // Kind: для confirm 1 = «Да», 0 = «Отмена»; для conflict 2 = «Перезагрузить»,
    // 1 = «Перезаписать», 0 = «Отмена»; для info/error 1 = «OK».
    private var continuation: CheckedContinuation<Int, Never>?

    /// Аналог QMessageBox.question → true, если пользователь подтвердил.
    func confirm(_ title: String, _ message: String) async -> Bool {
        await present(.init(title: title, message: message, kind: .confirm)) == 1
    }

    func info(_ title: String, _ message: String) async {
        _ = await present(.init(title: title, message: message, kind: .info))
    }

    func error(_ title: String, _ message: String) async {
        _ = await present(.init(title: title, message: message, kind: .error))
    }

    /// Трёхвариантный диалог: файл каталога изменили на диске (в общей папке)
    /// после того, как мы его открыли.
    func conflict(_ title: String, _ message: String) async -> ConflictChoice {
        switch await present(.init(title: title, message: message, kind: .conflict)) {
        case 2: return .reload
        case 1: return .overwrite
        default: return .cancel
        }
    }

    private func present(_ request: Request) async -> Int {
        // Если предыдущий алерт ещё висит — закрываем его как «отмену».
        continuation?.resume(returning: 0)
        continuation = nil
        return await withCheckedContinuation { cont in
            self.continuation = cont
            self.current = request
        }
    }

    /// Вызывается кнопками алерта из UI.
    func resolve(_ value: Int) {
        current = nil
        let cont = continuation
        continuation = nil
        cont?.resume(returning: value)
    }
}

// MARK: - Хост-модификатор

/// Подключает единственный алерт-хост к иерархии (в корне TabView).
struct DialogHost: ViewModifier {
    @ObservedObject var dialogs: DialogCoordinator

    func body(content: Content) -> some View {
        content.alert(
            dialogs.current?.title ?? "",
            isPresented: Binding(
                get: { dialogs.current != nil },
                set: { if !$0 { dialogs.resolve(0) } }
            ),
            presenting: dialogs.current
        ) { request in
            switch request.kind {
            case .confirm:
                Button("Yes", role: .destructive) { dialogs.resolve(1) }
                Button("Cancel", role: .cancel) { dialogs.resolve(0) }
            case .info, .error:
                Button("OK", role: .cancel) { dialogs.resolve(1) }
            case .conflict:
                Button("Reload from disk") { dialogs.resolve(2) }
                Button("Overwrite", role: .destructive) { dialogs.resolve(1) }
                Button("Cancel", role: .cancel) { dialogs.resolve(0) }
            }
        } message: { request in
            Text(request.message)
        }
    }
}

extension View {
    func dialogHost(_ dialogs: DialogCoordinator) -> some View {
        modifier(DialogHost(dialogs: dialogs))
    }
}
