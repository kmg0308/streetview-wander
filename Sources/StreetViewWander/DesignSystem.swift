import SwiftUI

enum WanderTheme {
    static let background = Color(red: 0.010, green: 0.012, blue: 0.016)
    static let surface = Color(red: 0.050, green: 0.058, blue: 0.070)
    static let elevatedSurface = Color(red: 0.066, green: 0.077, blue: 0.092)
    static let control = Color(red: 0.074, green: 0.086, blue: 0.102)
    static let controlHover = Color(red: 0.100, green: 0.118, blue: 0.140)
    static let selectedControl = Color(red: 0.090, green: 0.145, blue: 0.170)
    static let border = Color.white.opacity(0.105)
    static let subtleBorder = Color.white.opacity(0.065)
    static let highlightBorder = Color.white.opacity(0.16)
    static let primaryText = Color.white.opacity(0.94)
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.42)
    static let accent = Color(red: 0.42, green: 0.78, blue: 0.96)
    static let accentFill = Color(red: 0.125, green: 0.360, blue: 0.480)
    static let accentFillPressed = Color(red: 0.095, green: 0.290, blue: 0.390)
    static let warning = Color(red: 1.0, green: 0.73, blue: 0.32)
    static let danger = Color(red: 1.0, green: 0.58, blue: 0.48)

    static let cardRadius: CGFloat = 8
    static let controlRadius: CGFloat = 10
    static let compactControlRadius: CGFloat = 8
    static let buttonHeight: CGFloat = 34
    static let iconButtonSize: CGFloat = 34
    static let compactIconButtonSize: CGFloat = 30
}

struct WanderBackdrop: View {
    var body: some View {
        WanderTheme.background
    }
}

struct WanderSurfaceModifier: ViewModifier {
    var elevated = false
    var radius = WanderTheme.cardRadius

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let fill = elevated ? WanderTheme.elevatedSurface : WanderTheme.surface

        content
            .background {
                shape.fill(fill)
            }
            .overlay {
                shape.stroke(elevated ? WanderTheme.border : WanderTheme.subtleBorder, lineWidth: 1)
            }
    }
}

extension View {
    func wanderSurface(elevated: Bool = false, radius: CGFloat = WanderTheme.cardRadius) -> some View {
        modifier(WanderSurfaceModifier(elevated: elevated, radius: radius))
    }
}

struct WanderControlChrome: View {
    var isActive = false
    var isPressed = false
    var isProminent = false
    var cornerRadius = WanderTheme.controlRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape.fill(fillColor)
            shape.stroke(strokeColor, lineWidth: 1)
        }
    }

    private var fillColor: Color {
        if isProminent {
            return isPressed ? WanderTheme.accentFillPressed : WanderTheme.accentFill
        }
        if isActive {
            return WanderTheme.selectedControl.opacity(isPressed ? 0.86 : 1)
        }
        return isPressed ? WanderTheme.controlHover : WanderTheme.control
    }

    private var strokeColor: Color {
        if isProminent {
            return WanderTheme.accent.opacity(isPressed ? 0.50 : 0.36)
        }
        if isActive {
            return WanderTheme.accent.opacity(0.24)
        }
        return isPressed ? WanderTheme.highlightBorder : WanderTheme.subtleBorder
    }
}

struct WanderPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(WanderTheme.primaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, prominent ? 15 : 12)
            .frame(height: WanderTheme.buttonHeight)
            .background {
                WanderControlChrome(
                    isActive: selected,
                    isPressed: configuration.isPressed,
                    isProminent: prominent,
                    cornerRadius: prominent ? WanderTheme.buttonHeight / 2 : WanderTheme.controlRadius
                )
            }
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct WanderIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WanderTheme.primaryText)
            .frame(width: WanderTheme.iconButtonSize, height: WanderTheme.iconButtonSize)
            .background {
                WanderControlChrome(
                    isPressed: configuration.isPressed,
                    isProminent: prominent,
                    cornerRadius: WanderTheme.controlRadius
                )
            }
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
    }
}

struct WanderCompactIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(selected ? WanderTheme.primaryText : WanderTheme.secondaryText)
            .frame(width: WanderTheme.compactIconButtonSize, height: WanderTheme.compactIconButtonSize)
            .background {
                WanderControlChrome(
                    isPressed: configuration.isPressed,
                    isProminent: selected,
                    cornerRadius: WanderTheme.compactControlRadius
                )
            }
            .opacity(isEnabled ? 1 : 0.48)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
    }
}

struct WanderSegmentButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(selected ? WanderTheme.primaryText : WanderTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .background {
                if selected || configuration.isPressed {
                    WanderControlChrome(
                        isActive: selected,
                        isPressed: configuration.isPressed,
                        cornerRadius: WanderTheme.compactControlRadius
                    )
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: WanderTheme.compactControlRadius, style: .continuous))
    }
}

struct WanderFilterMenuLabel: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(title.uppercased())  \(value)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WanderTheme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(WanderTheme.tertiaryText)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity)
        .frame(height: WanderTheme.buttonHeight)
        .background {
            WanderControlChrome()
        }
    }
}
