#if os(macOS)
import SwiftUI

/// Push button: 28 pt high, shows hover and pressed states.
struct TKButtonStyle: ButtonStyle {
    enum Kind { case normal, primary, destructive }
    var kind: Kind = .normal

    func makeBody(configuration: Configuration) -> some View {
        TKButtonBody(configuration: configuration, kind: kind)
    }
}

private struct TKButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: TKButtonStyle.Kind
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(size: Theme.body, weight: kind == .normal ? .regular : .semibold))
            .foregroundStyle(kind == .normal ? Theme.textPrimary : Color.white)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minWidth: Theme.controlHeight, minHeight: Theme.controlHeight)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.buttonRadius)
                    .strokeBorder(Theme.buttonBorder, lineWidth: kind == .normal ? 1 : 0)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { hovering = $0 && isEnabled }
    }

    @ViewBuilder private var background: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.buttonRadius)
        switch kind {
        case .normal:
            shape.fill(configuration.isPressed ? Theme.buttonPressed : hovering ? Theme.buttonHover : Theme.buttonBackground)
        case .primary:
            shape.fill(Theme.accentFill).brightness(configuration.isPressed ? -0.12 : hovering ? -0.06 : 0)
        case .destructive:
            shape.fill(Theme.dangerFill).brightness(configuration.isPressed ? -0.12 : hovering ? -0.06 : 0)
        }
    }
}

/// Rounded white/dark box used for each section.
struct TKGroup<Content: View>: View {
    let content: Content
    var borderColor: Color = Theme.separator
    init(border: Color = Theme.separator, @ViewBuilder content: () -> Content) {
        self.content = content(); self.borderColor = border
    }
    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Theme.groupRadius).fill(Theme.groupBackground))
            .overlay(RoundedRectangle(cornerRadius: Theme.groupRadius).strokeBorder(borderColor, lineWidth: 1))
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: Theme.caption, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .padding(.leading, 4)
            .accessibilityAddTraits(.isHeader)
    }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8
    var body: some View { Circle().fill(color).frame(width: size, height: size).accessibilityHidden(true) }
}
#endif
