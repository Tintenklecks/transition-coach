import CoreText
import SwiftUI

// MARK: - Palette

/// The "Signal" design tokens.
///
/// Brand accent (`accent`) and semantic status colors are deliberately kept apart:
/// status colors communicate schedule state and are never tinted with the brand.
enum Signal {
    // Surfaces
    static let background = Color(hex: 0x0B0B0F)
    static let surface = Color(hex: 0x16161C)
    static let hairline = Color(hex: 0x232329)
    static let border = Color(hex: 0x2A2A32)
    static let inactive = Color(hex: 0x3A3A42)
    static let restingBackground = Color(hex: 0xF7F7F3)
    static let restingSurface = Color.white
    static let restingInk = Color(hex: 0x171719)
    static let restingSecondary = Color(hex: 0x6F716B)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x8A877E)

    // Brand accent
    static let accent = Color(hex: 0xF4C430)

    // Semantic status — functional signals, never brand-tinted
    static let upcoming = Color(hex: 0x3E6FF2)
    static let now = Color(hex: 0xF4C430)
    static let late = Color(hex: 0xE5484D)
    static let complete = Color(hex: 0x2FBF71)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - Typography

/// Space Grotesk / JetBrains Mono when bundled, graceful system fallback otherwise.
///
/// The fonts are not shipped with the project yet. Drop the `.ttf` files into the
/// app target and add them to `UIAppFonts` in Info.plist — this layer picks them up
/// automatically, no call sites change.
enum SignalFont {
    private static func isRegistered(_ postScriptName: String) -> Bool {
        let font = CTFontCreateWithName(postScriptName as CFString, 12, nil)
        let resolved = CTFontCopyPostScriptName(font) as String
        return resolved.caseInsensitiveCompare(postScriptName) == .orderedSame
    }

    private static let groteskAvailable = isRegistered("SpaceGrotesk-Bold")
    private static let monoAvailable = isRegistered("JetBrainsMono-Bold")

    private static func groteskName(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "SpaceGrotesk-Bold"
        case .semibold: "SpaceGrotesk-SemiBold"
        case .medium: "SpaceGrotesk-Medium"
        case .light, .thin, .ultraLight: "SpaceGrotesk-Light"
        default: "SpaceGrotesk-Regular"
        }
    }

    private static func monoName(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: "JetBrainsMono-Bold"
        case .semibold: "JetBrainsMono-SemiBold"
        case .medium: "JetBrainsMono-Medium"
        default: "JetBrainsMono-Regular"
        }
    }

    /// Headline / UI text.
    static func grotesk(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard groteskAvailable else {
            return .system(size: size, weight: weight)
        }
        return .custom(groteskName(weight), fixedSize: size)
    }

    /// Numbers, timers, durations, timestamps.
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        guard monoAvailable else {
            return .system(size: size, weight: weight, design: .monospaced)
        }
        return .custom(monoName(weight), fixedSize: size)
    }
}

extension View {
    /// Tight tracking used on large display type (-0.02em).
    func displayTracking(_ size: CGFloat) -> some View {
        tracking(size * -0.02)
    }

    /// Uppercase mono label with wide tracking (~0.12em) — section labels and eyebrows.
    func signalEyebrow(size: CGFloat = 12, color: Color = Signal.textSecondary, tracking: CGFloat = 0.12) -> some View {
        font(SignalFont.mono(size, .semibold))
            .textCase(.uppercase)
            .tracking(size * tracking)
            .foregroundStyle(color)
    }

    /// Hides the navigation chrome on platforms that draw one. The Signal screens
    /// supply their own headers, so the system bar would only double up.
    @ViewBuilder
    func hidingNavigationBar() -> some View {
#if os(iOS)
        toolbar(.hidden, for: .navigationBar)
#else
        self
#endif
    }
}

// MARK: - Schedule state

/// Background, ink and button colors for one schedule state.
///
/// Status colors are functional signals and stay untinted by the brand accent —
/// blue means "not yet", amber means "now", red means "at risk". Shared so the
/// watch shows the same color for the same state.
struct SignalStateStyle {
    let background: Color
    let ink: Color
    let buttonBackground: Color
    let buttonForeground: Color
    let prefersDarkChrome: Bool

    init(_ urgency: RoutineUrgency) {
        switch urgency {
        case .preparation:
            background = Signal.upcoming
            ink = .white
            buttonBackground = .white
            buttonForeground = Signal.upcoming
            prefersDarkChrome = true
        case .transition, .overdue:
            background = Signal.now
            ink = Signal.background
            buttonBackground = Signal.background
            buttonForeground = Signal.now
            prefersDarkChrome = false
        case .critical:
            background = Signal.late
            ink = .white
            buttonBackground = .white
            buttonForeground = Signal.late
            prefersDarkChrome = true
        case .completed:
            background = Signal.background
            ink = .white
            buttonBackground = Signal.accent
            buttonForeground = Signal.background
            prefersDarkChrome = true
        }
    }
}
// MARK: - Containers

/// Rounded dark card used to group rows. Rows inside are divided by `SignalHairline`.
struct SignalCard<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Signal.surface, in: .rect(cornerRadius: 18))
    }
}

struct SignalHairline: View {
    var body: some View {
        Rectangle()
            .fill(Signal.hairline)
            .frame(height: 1)
    }
}

// MARK: - Controls

/// Full-width primary button, 18pt radius. Colors flip with the surface it sits on.
struct SignalPrimaryButtonStyle: ButtonStyle {
    var background: Color = Signal.accent
    var foreground: Color = Signal.background

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(SignalFont.grotesk(17, .bold))
            .tracking(-0.17)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(background, in: .rect(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Pill toggle — amber when on, knob in the background color.
struct SignalToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
                .font(SignalFont.grotesk(16, .medium))
                .foregroundStyle(Signal.textPrimary)
            Spacer(minLength: 12)
            Capsule()
                .fill(configuration.isOn ? Signal.accent : Signal.hairline)
                .frame(width: 46, height: 28)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? Signal.background : Signal.textSecondary)
                        .frame(width: 22, height: 22)
                        .padding(3)
                }
                .onTapGesture {
                    withAnimation(.snappy(duration: 0.2)) {
                        configuration.isOn.toggle()
                    }
                }
                .accessibilityAddTraits(configuration.isOn ? [.isButton, .isSelected] : .isButton)
        }
    }
}

/// Circular -/+ pair: amber for increment, dark gray for decrement.
struct SignalStepper: View {
    @Binding var value: Int
    var range: ClosedRange<Int>
    var step: Int = 1
    var unit: String
    var diameter: CGFloat = 26
    var valueWidth: CGFloat = 38

    var body: some View {
        HStack(spacing: diameter > 28 ? 14 : 10) {
            button("minus", background: Signal.hairline, foreground: Signal.textPrimary) {
                value = max(range.lowerBound, value - step)
            }
            .disabled(value <= range.lowerBound)

            Text("\(value) \(unit)")
                .font(SignalFont.mono(diameter > 28 ? 15 : 13, .semibold))
                .foregroundStyle(Signal.textPrimary)
                .frame(minWidth: valueWidth)
                .contentTransition(.numericText())

            button("plus", background: Signal.accent, foreground: Signal.background) {
                value = min(range.upperBound, value + step)
            }
            .disabled(value >= range.upperBound)
        }
    }

    private func button(
        _ symbol: String,
        background: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.18)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: diameter * 0.42, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: diameter, height: diameter)
                .background(background, in: .circle)
        }
        .buttonStyle(.plain)
        .opacity(0.999) // keeps disabled state from dimming the whole row
    }
}

/// Thin rounded segments — amber for completed, dark gray for remaining.
struct SignalSegmentBar: View {
    let total: Int
    let filled: Int
    var height: CGFloat = 6
    var spacing: CGFloat = 6

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(index < filled ? Signal.accent : Signal.border)
                    .frame(height: height)
            }
        }
    }
}

/// Progress pips shown on the full-bleed live step, drawn in the on-color ink.
struct SignalStepPips: View {
    let total: Int
    let completed: Int
    let ink: Color

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<max(total, 1), id: \.self) { index in
                Capsule()
                    .fill(ink.opacity(index < completed ? 0.85 : 0.3))
                    .frame(width: 22, height: 5)
            }
        }
    }
}
