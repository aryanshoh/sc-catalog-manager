import SwiftUI
import AppKit

// Тема оформления. Раньше цвета были статическими константами; теперь `Theme`
// — это фасад над «текущей» палитрой (`Theme.current`), которую переключает
// AppState. Все вью читают Theme.* в своих body и наблюдают AppState, поэтому
// смена палитры перерисовывает весь интерфейс.
//
// Семантика оттенков одинакова во всех палитрах:
//   neutral[900] — фон панелей (sidebar, карточки, статус-бар)
//   neutral[800] — границы, разделители, hover, фон поля поиска
//   neutral[700] — усиленные границы, фон вторичной кнопки
//   neutral[400] — приглушённые подписи/иконки
//   neutral[300] — вторичный текст
//   neutral[200] — основной текст
//   neutral[100] — заголовки / самый сильный текст
//   accentRamp[800] — фон выбранной строки; accentRamp[100] — её текст
//   accentRamp[300] — акцентные подписи секций; accentRamp[200] — значения-акценты
// В светлых палитрах шкала просто инвертируется по светлоте.

enum ThemeID: String, CaseIterable, Identifiable {
    case dark, light, pinkGold

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .pinkGold: return "Pink & gold"
        }
    }

    var icon: String {
        switch self {
        case .dark: return "moon"
        case .light: return "sun.max"
        case .pinkGold: return "sunset"
        }
    }

    var palette: Palette {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .pinkGold: return .pinkGold
        }
    }
}

struct Palette {
    let bg: Color
    /// Если задан — фон контентной области рисуется вертикальным градиентом
    /// (используется в «закатной» теме).
    let bgGradient: [Color]?
    let text: Color
    let accent: Color
    /// Цвет текста на акцентной (primary) кнопке.
    let primaryText: Color
    let neutral: [Int: Color]
    let accentRamp: [Int: Color]
    /// Обводка вокруг залитых блоков (выделение, чипы, поле, кнопки). nil —
    /// без обводки; используется в «закатной» теме для золотистой рамки.
    let fillStroke: Color?
    let trafficRed: Color
    let trafficYellow: Color
    let trafficGreen: Color
    /// Системная схема — для нативных контролов (чекбоксы, курсор, скроллбары).
    let colorScheme: ColorScheme
    let windowBackground: NSColor
}

enum Theme {
    // Текущая палитра. Читается/меняется только на главном потоке (UI).
    nonisolated(unsafe) static var current: Palette = .dark

    // Цветовые аксессоры (совместимы со старым API).
    static var bg: Color { current.bg }
    static var text: Color { current.text }
    static var accent: Color { current.accent }
    static var primaryTextColor: Color { current.primaryText }
    static var trafficRed: Color { current.trafficRed }
    static var trafficYellow: Color { current.trafficYellow }
    static var trafficGreen: Color { current.trafficGreen }

    static func n(_ shade: Int) -> Color { current.neutral[shade] ?? current.text }
    static func a(_ shade: Int) -> Color { current.accentRamp[shade] ?? current.accent }

    /// Золотистая обводка вокруг заливок (nil в тёмной/светлой темах).
    static var fillStroke: Color? { current.fillStroke }

    /// Заливка фона контентной области — сплошной цвет или градиент.
    static var backgroundShape: AnyShapeStyle {
        if let gradient = current.bgGradient {
            return AnyShapeStyle(
                LinearGradient(colors: gradient, startPoint: .top, endPoint: .bottom)
            )
        }
        return AnyShapeStyle(current.bg)
    }

    // Радиусы / плотность — не зависят от темы.
    static let radiusSM: CGFloat = 6
    static let radiusMD: CGFloat = 8
    static let radiusLG: CGFloat = 12

    static let toolbarHeight: CGFloat = 52
    static let statusbarHeight: CGFloat = 26
    static let sidebarWidth: CGFloat = 232
    static let outlineWidth: CGFloat = 320
}

// MARK: - Палитры

extension Palette {
    /// Тёмная (Nocturne) — исходная тема.
    static let dark = Palette(
        bg: Color(hex: 0x161826),
        bgGradient: nil,
        text: Color(hex: 0xe9e9ed),
        accent: Color(hex: 0x9184d9),
        primaryText: Color(hex: 0x17131f),
        neutral: [
            900: Color(hex: 0x20202a),
            800: Color(hex: 0x2c2b38),
            700: Color(hex: 0x393949),
            600: Color(hex: 0x545365),
            500: Color(hex: 0x6c6b80),
            400: Color(hex: 0x8b8a9e),
            300: Color(hex: 0xacabba),
            200: Color(hex: 0xc7c6d2),
            100: Color(hex: 0xe3e2e9),
        ],
        accentRamp: [
            900: Color(hex: 0x20184e),
            800: Color(hex: 0x2d226d),
            500: Color(hex: 0x9184d9),
            300: Color(hex: 0xb2a9e5),
            200: Color(hex: 0xc4bdeb),
            100: Color(hex: 0xdcd8f3),
        ],
        fillStroke: nil,
        trafficRed: Color(hex: 0xec6a5e),
        trafficYellow: Color(hex: 0xf4bf50),
        trafficGreen: Color(hex: 0x61c454),
        colorScheme: .dark,
        windowBackground: NSColor(hex: 0x161826)
    )

    /// Светлая — тёплый кремовый фон (не чисто-белый), тёмный текст.
    static let light = Palette(
        bg: Color(hex: 0xfbf7ef),
        bgGradient: nil,
        text: Color(hex: 0x2b2a28),
        accent: Color(hex: 0x7166c9),
        primaryText: Color(hex: 0xffffff),
        neutral: [
            900: Color(hex: 0xf1ebdd),  // панели — чуть глубже фона
            800: Color(hex: 0xe6dfcf),  // границы/hover/поле
            700: Color(hex: 0xd7cfbc),
            600: Color(hex: 0xb8af9a),
            500: Color(hex: 0x948b78),
            400: Color(hex: 0x8a8271),  // приглушённые подписи
            300: Color(hex: 0x625c4f),  // вторичный текст
            200: Color(hex: 0x3e3a33),  // основной текст
            100: Color(hex: 0x29261f),  // заголовки
        ],
        accentRamp: [
            900: Color(hex: 0xeae6fa),
            800: Color(hex: 0xe7e2f7),  // фон выбранной строки
            500: Color(hex: 0x7166c9),
            300: Color(hex: 0x6e62c4),  // акцентные подписи
            200: Color(hex: 0x5f52bd),  // значения-акценты
            100: Color(hex: 0x4a3f97),  // текст выбранной строки
        ],
        fillStroke: nil,
        trafficRed: Color(hex: 0xec6a5e),
        trafficYellow: Color(hex: 0xf4bf50),
        trafficGreen: Color(hex: 0x61c454),
        colorScheme: .light,
        windowBackground: NSColor(hex: 0xfbf7ef)
    )

    /// Розово-золотая — тёплый закат (референс: небо Калифорнии/Австралии).
    /// Контентная область с мягким градиентом розовый → золотисто-персиковый.
    static let pinkGold = Palette(
        bg: Color(hex: 0xfee9e0),
        bgGradient: [Color(hex: 0xfbc6d6), Color(hex: 0xfed9b0)],
        text: Color(hex: 0x5a2e3e),
        accent: Color(hex: 0xb07496),  // мов/орхидея — среднее между фиолетом и золотом
        primaryText: Color(hex: 0xffffff),
        neutral: [
            900: Color(hex: 0xffe2d6),  // панели — мягкий тёплый персик
            800: Color(hex: 0xf7cfbd),  // границы/hover/поле — контраст, но помягче
            700: Color(hex: 0xf0bdab),
            600: Color(hex: 0xe0a08c),
            500: Color(hex: 0xc98974),
            400: Color(hex: 0xb07e6e),  // приглушённые подписи
            300: Color(hex: 0x8a4f52),  // вторичный текст (сливово-розовый)
            200: Color(hex: 0x6e3a44),  // основной текст
            100: Color(hex: 0x52272f),  // заголовки
        ],
        accentRamp: [  // мов/орхидея — среднее между фиолетом и золотом
            900: Color(hex: 0xf6e6ee),
            800: Color(hex: 0xf1d5df),  // фон выбранной строки/чипов
            500: Color(hex: 0xb07496),
            300: Color(hex: 0xa25f86),  // акцентные подписи
            200: Color(hex: 0x97517a),  // значения-акценты
            100: Color(hex: 0x804664),  // текст выбранной строки
        ],
        fillStroke: Color(hex: 0xd9a441),  // золотистая обводка вокруг заливок
        trafficRed: Color(hex: 0xec6a5e),
        trafficYellow: Color(hex: 0xf4bf50),
        trafficGreen: Color(hex: 0x61c454),
        colorScheme: .light,
        windowBackground: NSColor(hex: 0xfdd0c2)
    )
}

// MARK: - Хелперы hex

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xff) / 255.0
        let g = CGFloat((hex >> 8) & 0xff) / 255.0
        let b = CGFloat(hex & 0xff) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}
