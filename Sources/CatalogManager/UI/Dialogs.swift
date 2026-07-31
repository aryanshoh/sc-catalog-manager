import AppKit
import UniformTypeIdentifiers

// Тонкая обёртка над AppKit-диалогами — прямые аналоги QMessageBox и
// QFileDialog из Qt-версии. Все вызовы модальные и синхронные, что повторяет
// пошаговый управляющий поток оригинала (диалог гейтит действие).

@MainActor
enum Dialogs {
    /// Аналог QMessageBox.question → возвращает true, если пользователь выбрал «Да».
    static func confirm(_ title: String, _ message: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Выбор пользователя в диалоге конфликта записи.
    enum ConflictChoice { case reload, overwrite, cancel }

    /// Трёхвариантный диалог: файл каталога изменили на диске (в общей папке)
    /// после того, как мы его открыли.
    static func conflict(_ title: String, _ message: String) -> ConflictChoice {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reload from disk")  // alertFirstButtonReturn
        alert.addButton(withTitle: "Overwrite")           // alertSecondButtonReturn
        alert.addButton(withTitle: "Cancel")                 // alertThirdButtonReturn
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .reload
        case .alertSecondButtonReturn: return .overwrite
        default: return .cancel
        }
    }

    static func info(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    static func error(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Аналог QFileDialog.getOpenFileName для txt-файлов.
    static func openTextFile(title: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text]
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Аналог QFileDialog.getSaveFileName.
    static func saveTextFile(title: String, defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = title
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
