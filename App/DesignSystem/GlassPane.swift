import SwiftUI

extension EnvironmentValues {
    /// Opacity of the dark shade mixed into every glass pane. Brighter skies get more, so white ink
    /// keeps its contrast on a clear afternoon.
    @Entry var glassShade: Double = 0.2
}

struct GlassPaneChrome: ViewModifier {
    var isFocused = false
    var isPressed = false
    var cornerRadius: CGFloat = Theme.Glass.cornerRadius
    @Environment(\.glassShade) private var shade

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .foregroundStyle(Theme.Ink.primary)
            .background {
                shape.fill(Theme.Glass.focusSheen).opacity(isFocused ? 1 : 0)
            }
            .glassEffect(.regular.tint(Theme.Glass.shade.opacity(shade)), in: shape)
            .overlay {
                shape
                    .strokeBorder(Theme.Glass.focusRim, lineWidth: Theme.Glass.rimWidth)
                    .opacity(isFocused ? 1 : 0)
            }
            .background {
                LiftShadow(shape: shape).opacity(isFocused ? 1 : 0)
            }
            .scaleEffect(isFocused ? (isPressed ? Theme.Glass.pressedScale : Theme.Glass.focusScale) : 1)
            .animation(Theme.Motion.focus, value: isFocused)
            .animation(Theme.Motion.state, value: isPressed)
    }
}

/// A shadow that falls only outside the pane. A plain `.shadow` would also shadow the text, and a
/// shape behind translucent glass would darken the pane itself.
private struct LiftShadow<S: Shape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(Theme.Glass.liftShadow)
            .blur(radius: Theme.Glass.liftRadius)
            .offset(y: Theme.Glass.liftOffset)
            .mask {
                Rectangle()
                    .padding(-120)
                    .overlay { shape.blendMode(.destinationOut) }
                    .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

struct GlassPaneButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusBody(configuration: configuration)
    }

    private struct FocusBody: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .modifier(GlassPaneChrome(isFocused: isFocused, isPressed: configuration.isPressed))
        }
    }
}

extension View {
    func glassPane(focused: Bool = false) -> some View {
        modifier(GlassPaneChrome(isFocused: focused))
    }
}

struct PaneHeading: View {
    let text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            if let symbol {
                Image(systemName: symbol).fontWeight(.semibold)
            }
            Text(text.uppercased())
        }
        .font(Theme.Typeface.label)
        .tracking(Theme.Typeface.labelTracking)
        .foregroundStyle(Theme.Ink.tertiary)
        .accessibilityAddTraits(.isHeader)
    }
}
