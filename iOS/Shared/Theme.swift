import SwiftUI

// 1.3 look "A1 green LED" (docs/design-v1.3-restyle.md, docs/design/restyle-a1*.png).
// One place for the colours and the parts; compiled into both the iPhone app and the Apple Watch app
// (iOS/Shared), so it uses SwiftUI only. The look is always dark: it is made for a dark stage.

/// The A1 palette (design/restyle/make_a.py, THEMES["a1"]).
enum TK {
    /// Background.
    static let bg = Color(tkRGB: 0x000000)
    /// Top bar and the right rail.
    static let top = Color(tkRGB: 0x070707)
    /// Cards and buttons.
    static let panel = Color(tkRGB: 0x060606)
    /// Thin lines.
    static let stroke = Color(tkRGB: 0x2A2A2A)
    /// OK, playing, GO (glows).
    static let accent = Color(tkRGB: 0x3DFF7A)
    /// Small text inside GO.
    static let accentSoft = Color(tkRGB: 0x9AF5B7)
    /// Numbers and body text.
    static let read = Color(tkRGB: 0xEDEDED)
    /// Small decorative headings only (3.9:1 on black: never for text that matters).
    static let label = Color(tkRGB: 0x6B6B6B)
    /// Secondary text that matters (7:1 on black).
    static let dim = Color(tkRGB: 0x9A9A9A)
    /// An unlit meter segment.
    static let off = Color(tkRGB: 0x151515)
    /// An unlit LED.
    static let ledOff = Color(tkRGB: 0x3A3A3A)
    /// Stopped, All Notes Off.
    static let red = Color(tkRGB: 0xFF3B30)
    /// Text on the dark red ground of All Notes Off.
    static let redSoft = Color(tkRGB: 0xFF9A92)
    /// Dark red ground (All Notes Off, the main-lost bar).
    static let redGround = Color(tkRGB: 0x1A0605)
    /// A filled red button with white text (5:1; #FF3B30 with white is under 4.5:1).
    static let redFill = Color(tkRGB: 0xD70015)
    /// The backup is the main; warnings.
    static let yellow = Color(tkRGB: 0xFFB020)
    /// Dark yellow ground for warning bars.
    static let yellowGround = Color(tkRGB: 0x1F1503)
    /// "Next".
    static let blue = Color(tkRGB: 0x8AB4FF)
    /// Dark blue ground (switched-to-backup bar).
    static let blueGround = Color(tkRGB: 0x0A1222)
    /// GO key gradient, top and bottom; also the ground of a selected green key.
    static let keyTop = Color(tkRGB: 0x0E2416)
    static let keyBottom = Color(tkRGB: 0x050B07)
    /// Fader cap.
    static let cap = Color(tkRGB: 0x1A1A1A)
    static let capLine = Color(tkRGB: 0x555555)

    /// Thin line width ("2 px" in the drawings, which are at twice the point size).
    static let line: CGFloat = 1
    static let radius: CGFloat = 7

    /// Monospaced font that follows Dynamic Type (SF Mono).
    static func mono(_ style: Font.TextStyle, _ weight: Font.Weight = .bold) -> Font {
        .system(style, design: .monospaced, weight: weight)
    }
}

extension Color {
    /// 0xRRGGBB.
    init(tkRGB v: UInt32) {
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - Parts

/// A small round lamp with a glow of the same colour.
struct LED: View {
    var color: Color = TK.accent
    var on = true
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(on ? color : TK.ledOff)
            .frame(width: size, height: size)
            .shadow(color: on ? color.opacity(0.9) : .clear, radius: size * 0.6)
            .shadow(color: on ? color.opacity(0.5) : .clear, radius: size * 1.2)
            .accessibilityHidden(true)
    }
}

/// Spaced monospaced capitals ("NOW PLAYING", "SCENES"...). Decoration: VoiceOver reads `spoken`
/// (the localized words) when given, and skips the label otherwise.
struct SmallCaps: View {
    let text: String
    var color: Color = TK.label
    var spoken: String? = nil
    var style: Font.TextStyle = .caption2

    init(_ text: String, color: Color = TK.label, spoken: String? = nil, style: Font.TextStyle = .caption2) {
        self.text = text
        self.color = color
        self.spoken = spoken
        self.style = style
    }

    var body: some View {
        let t = Text(text).font(TK.mono(style)).tracking(2).foregroundStyle(color).lineLimit(1)
        if let spoken {
            t.accessibilityLabel(spoken)
        } else {
            t.accessibilityHidden(true)
        }
    }
}

/// A black display window with a tiny heading above monospaced digits (TEMPO, POSITION).
struct DisplayWindow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 7, weight: .bold, design: .monospaced)).tracking(1.5)
                .foregroundStyle(TK.label).lineLimit(1)
                .accessibilityHidden(true)
            content
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .fixedSize()  // a readout is never cut off ("1… B…"); the rest of the bar gives way
        .background(RoundedRectangle(cornerRadius: 4).fill(TK.bg))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(TK.stroke, lineWidth: TK.line))
    }
}

/// A row (or column) of square meter segments. `vu`: the top segments turn yellow, then red.
struct SegmentMeter: View {
    /// 0...1
    var value: Double
    var segments = 40
    var vertical = false
    var vu = false
    var color: Color = TK.accent
    var spacing: CGFloat = 2

    var body: some View {
        let v = value.isFinite ? min(1, max(0, value)) : 0
        let lit = Int((v * Double(segments)).rounded())
        Group {
            if vertical {
                VStack(spacing: spacing) {
                    ForEach(0..<segments, id: \.self) { k in cell(segments - 1 - k, lit) }
                }
            } else {
                HStack(spacing: spacing) {
                    ForEach(0..<segments, id: \.self) { i in cell(i, lit) }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func cell(_ i: Int, _ lit: Int) -> some View {
        RoundedRectangle(cornerRadius: 1).fill(i < lit ? segmentColor(i) : TK.off)
    }

    private func segmentColor(_ i: Int) -> Color {
        guard vu else { return color }
        if i >= segments - max(1, segments / 12) { return TK.red }
        if i >= segments - max(2, segments / 4) { return TK.yellow }
        return color
    }
}

/// The GO key: dark green gradient, a glowing green edge and a thin line along the top.
struct GoKeyBackground: View {
    var enabled = true
    var radius: CGFloat = 16

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        shape
            .fill(LinearGradient(colors: enabled ? [TK.keyTop, TK.keyBottom] : [TK.panel, TK.panel], startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(enabled ? TK.accent : TK.stroke, lineWidth: enabled ? 2 : TK.line))
            .overlay(alignment: .top) {
                if enabled {
                    Capsule().fill(TK.accent.opacity(0.6)).frame(height: 2)
                        .padding(.horizontal, radius * 0.6).padding(.top, 8)
                }
            }
            .shadow(color: enabled ? TK.accent.opacity(0.4) : .clear, radius: 8)
    }
}

/// All Notes Off: dark red ground, red edge (red text goes on top).
struct NotesOffBackground: View {
    var radius: CGFloat = 8
    var lineWidth: CGFloat = 1.5

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius)
        shape.fill(TK.redGround)
            .overlay(shape.fill(TK.red.opacity(0.12)))
            .overlay(shape.strokeBorder(TK.red, lineWidth: lineWidth))
    }
}

extension View {
    /// A card or button: near-black panel with a thin line (green, blue, red... for a state).
    func tkPanel(radius: CGFloat = TK.radius, fill: Color = TK.panel, stroke: Color = TK.stroke, lineWidth: CGFloat = TK.line) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(stroke, lineWidth: lineWidth))
    }
}

/// Buttons in the A1 look. `.plain`: panel with a thin line. `.green`: selected / go-ahead (dark green,
/// green line, green text). `.red`: All Notes Off style.
struct TKButtonStyle: ButtonStyle {
    enum Kind { case plain, green, red }
    var kind: Kind = .plain
    var radius: CGFloat = TK.radius
    var minHeight: CGFloat = 44

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration, kind: kind, radius: radius, minHeight: minHeight)
    }

    /// A view of its own, so that `isEnabled` is read where the button is.
    private struct KeyBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let radius: CGFloat
        let minHeight: CGFloat
        @Environment(\.isEnabled) private var isEnabled

        private var fg: Color {
            switch kind {
            case .plain: return TK.read
            case .green: return TK.accent
            case .red: return TK.red
            }
        }

        private var fill: Color {
            switch kind {
            case .plain: return TK.panel
            case .green: return TK.keyTop
            case .red: return TK.redGround
            }
        }

        private var line: Color {
            switch kind {
            case .plain: return TK.stroke
            case .green: return TK.accent
            case .red: return TK.red
            }
        }

        var body: some View {
            configuration.label
                .foregroundStyle(isEnabled ? fg : TK.dim)
                .padding(.horizontal, 14)
                .frame(minHeight: minHeight)
                .tkPanel(radius: radius, fill: fill, stroke: isEnabled ? line : TK.stroke, lineWidth: kind == .plain ? TK.line : 1.5)
                .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.6))
                .contentShape(RoundedRectangle(cornerRadius: radius))
        }
    }
}

/// A toggle drawn as a key: green when on (Session's Follow).
struct TKToggleKeyStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: { configuration.label }
            .buttonStyle(TKButtonStyle(kind: configuration.isOn ? .green : .plain, radius: 6, minHeight: 34))
            .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}
