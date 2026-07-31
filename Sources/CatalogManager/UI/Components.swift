import SwiftUI

// Переиспользуемые элементы интерфейса в стиле Nocturne: кнопки трёх видов,
// чипы-теги, секционные подписи и flow-раскладка (порт flow_layout.py).

enum ButtonKind {
    case primary, secondary, ghost
}

struct NocturneButton: View {
    let title: String
    var systemImage: String?
    var kind: ButtonKind = .secondary
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button {
            if isEnabled { action() }
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 12, weight: .medium))
                }
                Text(title)
            }
            .font(.system(size: 12.5, weight: kind == .primary ? .semibold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(background)
            .foregroundColor(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD))
            .opacity(isEnabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 && isEnabled }
    }

    private var background: Color {
        switch kind {
        case .primary:
            if !isEnabled { return Theme.n(700) }
            return hovering ? Theme.a(300) : Theme.accent
        case .secondary:
            return hovering ? Theme.n(700) : Theme.n(800)
        case .ghost:
            return hovering ? Theme.n(800) : .clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return isEnabled ? Theme.primaryTextColor : Theme.n(400)
        case .secondary: return isEnabled ? Theme.n(100) : Theme.n(500)
        case .ghost: return isEnabled ? Theme.n(200) : Theme.n(500)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary: return .clear
        case .secondary: return Theme.n(700)
        case .ghost: return isEnabled ? Theme.n(700) : Theme.n(800)
        }
    }
}

/// Небольшая кнопка для панели над деревом каталога (развернуть/свернуть все).
struct OutlineToolButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 11))
                Text(title).font(.system(size: 11.5))
            }
            .foregroundColor(hovering ? Theme.n(100) : Theme.n(300))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(hovering ? Theme.n(700) : Theme.n(800))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .stroke(Theme.fillStroke ?? .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

enum TagKind {
    case accent, outline
}

struct TagChip: View {
    let text: String
    let kind: TagKind

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(kind == .accent ? Theme.a(800) : Color.clear)
            .foregroundColor(kind == .accent ? Theme.a(100) : Theme.n(300))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusSM)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSM))
    }

    private var strokeColor: Color {
        switch kind {
        case .accent: return Theme.fillStroke ?? .clear   // золотая обводка в закатной теме
        case .outline: return Theme.n(700)
        }
    }
}

struct SectionCaption: View {
    let text: String
    var color: Color = Theme.n(400)

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1)
            .foregroundColor(color)
    }
}

/// Flow-раскладка с переносом по строкам — порт FlowLayout из flow_layout.py.
struct FlowLayout: Layout {
    var hSpacing: CGFloat = 6
    var vSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, totalWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0; y += rowHeight + vSpacing; rowHeight = 0
            }
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
            totalWidth = max(totalWidth, x - hSpacing)
        }
        return CGSize(width: min(totalWidth, maxWidth), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let maxWidth = bounds.width
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0; y += rowHeight + vSpacing; rowHeight = 0
            }
            sub.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: ProposedViewSize(size))
            x += size.width + hSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
