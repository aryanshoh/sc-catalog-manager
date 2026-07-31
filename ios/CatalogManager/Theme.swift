import SwiftUI

// Тема оформления для iOS-версии. Значения палитр перенесены один-в-один из
// macOS-версии (Nocturne / светлая / розово-золотая), но без NSColor —
// оконного хрома на iOS нет, поэтому windowBackground не нужен.
//
// Семантика оттенков одинакова во всех палитрах:
//   neutral[900] — фон панелей/карточек
//   neutral[800] — границы, разделители, фон поля поиска
//   neutral[700] — усиленные границы, фон вторичной кнопки
//   neutral[400] — приглушённые подписи/иконки
//   neutral[300] — вторичный текст
//   neutral[200] — основной текст
//   neutral[100] — заголовки
//   accentRamp[800] — фон выбранной строки; accentRamp[100] — её текст

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
    /// Если задан — фон контента рисуется вертикальным градиентом (закатная тема).
    let bgGradient: [Color]?
    let text: Color
    let accent: Color
    let primaryText: Color
    let neutral: [Int: Color]
    let accentRamp: [Int: Color]
    /// Золотистая обводка вокруг заливок (nil в тёмной/светлой темах).
    let fillStroke: Color?
    let colorScheme: ColorScheme
}

enum Theme {
    nonisolated(unsafe) static var current: Palette = .dark

    static var bg: Color { current.bg }
    static var text: Color { current.text }
    static var accent: Color { current.accent }
    static var primaryTextColor: Color { current.primaryText }

    static func n(_ shade: Int) -> Color { current.neutral[shade] ?? current.text }
    static func a(_ shade: Int) -> Color { current.accentRamp[shade] ?? current.accent }

    static var fillStroke: Color? { current.fillStroke }

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
}

/// Фон контентной области (сплошной цвет или градиент), растянутый под safe area.
/// AnyShapeStyle сам по себе не View, поэтому заворачиваем в прямоугольник.
///
/// `theme` хранится как свойство специально: без него у структуры не было бы
/// входных данных, и SwiftUI считал бы все экземпляры одинаковыми и не
/// перерисовывал body при смене темы (фон «застревал» бы на старой палитре).
struct ThemedBackground: View {
    let theme: ThemeID

    var body: some View {
        Rectangle().fill(Theme.backgroundShape).ignoresSafeArea()
    }
}

// MARK: - Палитры

extension Palette {
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
        colorScheme: .dark
    )

    static let light = Palette(
        bg: Color(hex: 0xfbf7ef),
        bgGradient: nil,
        text: Color(hex: 0x2b2a28),
        accent: Color(hex: 0x7166c9),
        primaryText: Color(hex: 0xffffff),
        neutral: [
            900: Color(hex: 0xf1ebdd),
            800: Color(hex: 0xe6dfcf),
            700: Color(hex: 0xd7cfbc),
            600: Color(hex: 0xb8af9a),
            500: Color(hex: 0x948b78),
            400: Color(hex: 0x8a8271),
            300: Color(hex: 0x625c4f),
            200: Color(hex: 0x3e3a33),
            100: Color(hex: 0x29261f),
        ],
        accentRamp: [
            900: Color(hex: 0xeae6fa),
            800: Color(hex: 0xe7e2f7),
            500: Color(hex: 0x7166c9),
            300: Color(hex: 0x6e62c4),
            200: Color(hex: 0x5f52bd),
            100: Color(hex: 0x4a3f97),
        ],
        fillStroke: nil,
        colorScheme: .light
    )

    static let pinkGold = Palette(
        bg: Color(hex: 0xfee9e0),
        bgGradient: [Color(hex: 0xfbc6d6), Color(hex: 0xfed9b0)],
        text: Color(hex: 0x5a2e3e),
        accent: Color(hex: 0xb07496),
        primaryText: Color(hex: 0xffffff),
        neutral: [
            900: Color(hex: 0xffe2d6),
            800: Color(hex: 0xf7cfbd),
            700: Color(hex: 0xf0bdab),
            600: Color(hex: 0xe0a08c),
            500: Color(hex: 0xc98974),
            400: Color(hex: 0xb07e6e),
            300: Color(hex: 0x8a4f52),
            200: Color(hex: 0x6e3a44),
            100: Color(hex: 0x52272f),
        ],
        accentRamp: [
            900: Color(hex: 0xf6e6ee),
            800: Color(hex: 0xf1d5df),
            500: Color(hex: 0xb07496),
            300: Color(hex: 0xa25f86),
            200: Color(hex: 0x97517a),
            100: Color(hex: 0x804664),
        ],
        fillStroke: Color(hex: 0xd9a441),
        colorScheme: .light
    )
}

// MARK: - Хелпер hex

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xff) / 255.0
        let g = Double((hex >> 8) & 0xff) / 255.0
        let b = Double(hex & 0xff) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
