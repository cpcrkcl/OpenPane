//
//  OpenPaneButtonStyles.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/7/26.
//

import SwiftUI

private struct OpenPaneCompactToolbarControlsKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var openPaneCompactToolbarControls: Bool {
        get { self[OpenPaneCompactToolbarControlsKey.self] }
        set { self[OpenPaneCompactToolbarControlsKey.self] = newValue }
    }
}

private struct OpenPaneAdaptiveToolbarLabelStyle: LabelStyle {
    let usesCompactControls: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if usesCompactControls {
            configuration.icon
                .accessibilityRepresentation {
                    configuration.title
                }
        } else {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
            }
        }
    }
}

struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.openPaneCompactToolbarControls) private var usesCompactControls

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .labelStyle(OpenPaneAdaptiveToolbarLabelStyle(usesCompactControls: usesCompactControls))
            .foregroundStyle(isEnabled ? CatppuccinMochaTheme.crust : CatppuccinMochaTheme.mutedText)
            .frame(
                width: usesCompactControls ? 28 : nil,
                height: usesCompactControls ? 28 : nil
            )
            .padding(.horizontal, usesCompactControls ? 0 : 10)
            .padding(.vertical, usesCompactControls ? 0 : 6)
            .background(
                primaryBackground(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                    .stroke(
                        isEnabled ? CatppuccinMochaTheme.lavender.opacity(0.55) : CatppuccinMochaTheme.surface1.opacity(0.45),
                        lineWidth: CatppuccinMochaTheme.hairlineBorderWidth
                    )
            }
            .opacity(isEnabled ? 1 : 0.58)
    }

    private func primaryBackground(isPressed: Bool) -> Color {
        guard isEnabled else {
            return CatppuccinMochaTheme.surface0.opacity(0.55)
        }

        return isPressed ? CatppuccinMochaTheme.lavender.opacity(0.78) : CatppuccinMochaTheme.accent
    }
}

struct SecondaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.openPaneCompactToolbarControls) private var usesCompactControls

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .labelStyle(OpenPaneAdaptiveToolbarLabelStyle(usesCompactControls: usesCompactControls))
            .foregroundStyle(isEnabled ? CatppuccinMochaTheme.primaryText : CatppuccinMochaTheme.mutedText)
            .frame(
                width: usesCompactControls ? 28 : nil,
                height: usesCompactControls ? 28 : nil
            )
            .padding(.horizontal, usesCompactControls ? 0 : 9)
            .padding(.vertical, usesCompactControls ? 0 : 6)
            .background(
                secondaryBackground(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                    .stroke(
                        isEnabled ? CatppuccinMochaTheme.surface1 : CatppuccinMochaTheme.surface1.opacity(0.45),
                        lineWidth: CatppuccinMochaTheme.hairlineBorderWidth
                    )
            }
            .opacity(isEnabled ? 1 : 0.58)
    }

    private func secondaryBackground(isPressed: Bool) -> Color {
        guard isEnabled else {
            return CatppuccinMochaTheme.surface0.opacity(0.42)
        }

        return isPressed ? CatppuccinMochaTheme.surface2.opacity(0.72) : CatppuccinMochaTheme.surface0.opacity(0.9)
    }
}

struct DestructiveActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.openPaneCompactToolbarControls) private var usesCompactControls

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .labelStyle(OpenPaneAdaptiveToolbarLabelStyle(usesCompactControls: usesCompactControls))
            .foregroundStyle(isEnabled ? CatppuccinMochaTheme.red : CatppuccinMochaTheme.mutedText)
            .frame(
                width: usesCompactControls ? 28 : nil,
                height: usesCompactControls ? 28 : nil
            )
            .padding(.horizontal, usesCompactControls ? 0 : 9)
            .padding(.vertical, usesCompactControls ? 0 : 6)
            .background(
                destructiveBackground(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                    .stroke(
                        isEnabled ? CatppuccinMochaTheme.red.opacity(0.48) : CatppuccinMochaTheme.surface1.opacity(0.45),
                        lineWidth: CatppuccinMochaTheme.hairlineBorderWidth
                    )
            }
            .opacity(isEnabled ? 1 : 0.58)
    }

    private func destructiveBackground(isPressed: Bool) -> Color {
        guard isEnabled else {
            return CatppuccinMochaTheme.surface0.opacity(0.42)
        }

        return isPressed ? CatppuccinMochaTheme.red.opacity(0.2) : CatppuccinMochaTheme.red.opacity(0.1)
    }
}

struct ToolbarIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .labelStyle(.iconOnly)
            .foregroundStyle(isEnabled ? CatppuccinMochaTheme.secondaryText : CatppuccinMochaTheme.mutedText)
            .frame(width: 28, height: 28)
            .background(
                iconBackground(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                    .stroke(CatppuccinMochaTheme.surface1.opacity(isEnabled ? 0.75 : 0.4), lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
            }
            .opacity(isEnabled ? 1 : 0.55)
    }

    private func iconBackground(isPressed: Bool) -> Color {
        guard isEnabled else {
            return CatppuccinMochaTheme.surface0.opacity(0.36)
        }

        return isPressed ? CatppuccinMochaTheme.surface2.opacity(0.68) : CatppuccinMochaTheme.surface0.opacity(0.72)
    }
}

struct PaneTabButtonStyle: ButtonStyle {
    let isActive: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isActive ? .semibold : .medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                backgroundColor(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
            )
            .overlay {
                RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
                    .stroke(borderColor, lineWidth: CatppuccinMochaTheme.hairlineBorderWidth)
            }
            .opacity(isEnabled ? 1 : 0.55)
    }

    private var foregroundColor: Color {
        guard isEnabled else {
            return CatppuccinMochaTheme.mutedText
        }

        return isActive ? CatppuccinMochaTheme.primaryText : CatppuccinMochaTheme.secondaryText
    }

    private var borderColor: Color {
        guard isEnabled else {
            return CatppuccinMochaTheme.surface1.opacity(0.38)
        }

        return isActive ? CatppuccinMochaTheme.accent.opacity(0.48) : CatppuccinMochaTheme.surface1.opacity(0.58)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        guard isEnabled else {
            return CatppuccinMochaTheme.surface0.opacity(0.36)
        }

        if isPressed {
            return CatppuccinMochaTheme.surface2.opacity(0.68)
        }

        return isActive ? CatppuccinMochaTheme.surface1.opacity(0.88) : CatppuccinMochaTheme.surface0.opacity(0.58)
    }
}

struct PaneTabCloseButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isEnabled ? CatppuccinMochaTheme.mutedText : CatppuccinMochaTheme.overlay0.opacity(0.55))
            .frame(width: 20, height: 20)
            .background(
                closeBackground(isPressed: configuration.isPressed),
                in: RoundedRectangle(cornerRadius: CatppuccinMochaTheme.cornerRadiusSmall)
            )
            .opacity(isEnabled ? 1 : 0.45)
    }

    private func closeBackground(isPressed: Bool) -> Color {
        guard isEnabled else {
            return Color.clear
        }

        return isPressed ? CatppuccinMochaTheme.surface2.opacity(0.62) : Color.clear
    }
}
