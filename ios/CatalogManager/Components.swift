import SwiftUI

// Переиспользуемые элементы интерфейса в стиле Nocturne, адаптированные под
// touch: вместо hover-состояний (macOS) используется нажатие (pressed) через
// ButtonStyle, увеличены зоны нажатия.

enum ButtonKind { case primary, secondary, ghost }

struct NocturneButton: View {
    let title: String
    var systemImage: String?
    var kind: ButtonKind = .secondary
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            if isEnabled { action() }
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.system(size: 13, weight: .medium))
                }
                Text(title)
            }
            .font(.system(size: 14, weight: kind == .primary ? .semibold : .regular))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
        }
        .buttonStyle(NocturneButtonStyle(kind: kind, isEnabled: isEnabled))
        .disabled(!isEnabled)
    }
}

private struct NocturneButtonStyle: ButtonStyle {
    let kind: ButtonKind
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 16)
            .background(background(pressed: configuration.isPressed))
            .foregroundColor(foreground)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .stroke(borderColor, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMD))
            .opacity(isEnabled ? 1 : 0.55)
    }

    private func background(pressed: Bool) -> Color {
        switch kind {
        case .primary:
            if !isEnabled { return Theme.n(700) }
            return pressed ? Theme.a(300) : Theme.accent
        case .secondary:
            return pressed ? Theme.n(700) : Theme.n(800)
        case .ghost:
            return pressed ? Theme.n(800) : .clear
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

enum TagKind { case accent, outline }

struct TagChip: View {
    let text: String
    let kind: TagKind

    var body: some View {
        Text(text)
            .font(.system(size: 12.5))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
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
        case .accent: return Theme.fillStroke ?? .clear
        case .outline: return Theme.n(700)
        }
    }
}

struct SectionCaption: View {
    let text: String
    var color: Color = Theme.n(400)

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1)
            .foregroundColor(color)
    }
}

/// Flow-раскладка с переносом по строкам (для чипов категорий/тегов).
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
