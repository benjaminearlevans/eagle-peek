//
//  GlassEffectModifier.swift
//  EagleViewer
//
//  Created on 2025/02/14
//

import SwiftUI

struct RegularGlassEffectModifier: ViewModifier {
    let interactive: Bool
    @GestureState private var isPressed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.Radius.control, style: .continuous)

        if reduceTransparency {
            interactiveFallback(content: content, shape: shape)
        } else if #available(iOS 26.0, *) {
            if interactive {
                content.glassEffect(.regular.interactive())
            } else {
                content.glassEffect(.regular)
            }
        } else {
            interactiveFallback(content: content, shape: shape, usesMaterial: true)
        }
    }

    @ViewBuilder
    private func interactiveFallback(
        content: Content,
        shape: RoundedRectangle,
        usesMaterial: Bool = false
    ) -> some View {
        let base = content.background(
            usesMaterial ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(AppTheme.Colors.glassFallbackFill),
            in: shape
        )

        if interactive {
            base
                .overlay(
                    shape.fill(AppTheme.Colors.glassPressedFill.opacity(isPressed ? 0.7 : 0))
                )
                .animation(.easeInOut(duration: 0.15), value: isPressed)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isPressed) { _, state, _ in
                            state = true
                        }
                )
        } else {
            base
        }
    }
}

extension View {
    func regularGlassEffect(interactive: Bool) -> some View {
        modifier(RegularGlassEffectModifier(interactive: interactive))
    }
}

struct GlassBackgroundModifier<BackgroundShape: Shape>: ViewModifier {
    let shape: BackgroundShape
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(AppTheme.Colors.glassFallbackFill, in: shape)
                .clipShape(shape)
        } else if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(.thinMaterial, in: shape)
                .clipShape(shape)
        }
    }
}

extension View {
    func glassBackground<BackgroundShape: Shape>(in shape: BackgroundShape) -> some View {
        modifier(GlassBackgroundModifier(shape: shape))
    }
}

struct GlassProminentButtonModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

extension View {
    func glassProminentButton() -> some View {
        modifier(GlassProminentButtonModifier())
    }
}

struct LegacyAccentForegroundModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.foregroundColor(.primary)
        } else {
            content.foregroundColor(.accentColor)
        }
    }
}

extension View {
    func legacyAccentForeground() -> some View {
        modifier(LegacyAccentForegroundModifier())
    }
}
