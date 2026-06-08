//
//  OpenPaneButtonStyles.swift
//  OpenPane
//
//  Created by Christopher Rego on 6/7/26.
//

import SwiftUI

struct PrimaryActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isEnabled ? CatppuccinMochaTheme.crust : CatppuccinMochaTheme.mutedText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isEnabled ? CatppuccinMochaTheme.primaryText : CatppuccinMochaTheme.mutedText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
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

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(isEnabled ? CatppuccinMochaTheme.red : CatppuccinMochaTheme.mutedText)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
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
