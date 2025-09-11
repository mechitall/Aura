import SwiftUI
import UIKit

// Central design tokens & reusable styles for Aura.
struct AuraDesignSystem {
    struct Colors {
        static let gradientStart = Color(red: 0.20, green: 0.05, blue: 0.45)
        static let gradientMid   = Color(red: 0.38, green: 0.15, blue: 0.75)
        static let gradientEnd   = Color(red: 0.08, green: 0.10, blue: 0.25)
        static let accent        = Color(red: 0.60, green: 0.35, blue: 0.95)
        static let accentSecondary = Color(red: 0.35, green: 0.65, blue: 0.95)
        static let destructive   = Color.red
        static let positive      = Color.green
        static let warning       = Color.orange
        // Pastel palette inspired by soft wellness dashboards (suitable for light mode aesthetics)
        static let pastelPink = Color(red: 1.00, green: 0.82, blue: 0.92)
        static let pastelRose = Color(red: 0.98, green: 0.70, blue: 0.90)
        static let pastelLavender = Color(red: 0.85, green: 0.72, blue: 0.98)
        static let pastelIndigo = Color(red: 0.68, green: 0.60, blue: 0.97)
        static let pastelPeach = Color(red: 1.00, green: 0.80, blue: 0.78)
        static let pastelOrange = Color(red: 1.00, green: 0.74, blue: 0.62)
        static let pastelYellow = Color(red: 1.00, green: 0.86, blue: 0.64)
        static let pastelBackground = Color(red: 0.98, green: 0.93, blue: 0.99)
        static let pastelAccent = Color(red: 0.90, green: 0.55, blue: 0.98)
    }
    struct Gradients {
        static var background: LinearGradient {
            LinearGradient(
                gradient: Gradient(colors: [Colors.gradientStart, Colors.gradientMid, Colors.gradientEnd]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        static var accentRadial: RadialGradient {
            RadialGradient(gradient: Gradient(colors: [Colors.accent.opacity(0.6), Colors.accent.opacity(0.05)]), center: .center, startRadius: 40, endRadius: 220)
        }
        static var pastelBackground: LinearGradient {
            LinearGradient(
                gradient: Gradient(colors: [
                    Colors.pastelBackground,
                    Colors.pastelLavender.opacity(0.55),
                    Colors.pastelRose.opacity(0.6)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        static var layeredWaves: [Color] {[
            Colors.pastelRose.opacity(0.55),
            Colors.pastelLavender.opacity(0.7),
            Colors.pastelIndigo.opacity(0.8)
        ]}
    }
    struct Blur {
        static func glass(_ radius: CGFloat = 18) -> some ViewModifier { GlassModifier(cornerRadius: radius) }
        private struct GlassModifier: ViewModifier {
            let cornerRadius: CGFloat
            func body(content: Content) -> some View {
                content
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            }
        }
    }
    struct Typography {
        static let largeTitle = Font.system(size: 34, weight: .bold, design: .rounded)
        static let sectionTitle = Font.system(size: 20, weight: .semibold, design: .rounded)
        static let body = Font.system(size: 16, weight: .regular, design: .rounded)
        static let caption = Font.system(size: 12, weight: .medium, design: .rounded)
    }
    struct Motion {
        static func spring() -> Animation { .spring(response: 0.55, dampingFraction: 0.85) }
        static func subtlePulse(duration: Double = 2.5) -> Animation { .easeInOut(duration: duration).repeatForever(autoreverses: true) }
    }
    struct Haptics {
        static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    }
}

// MARK: - Reusable Components
struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    @ViewBuilder let content: Content
    init(cornerRadius: CGFloat = 20, padding: CGFloat = 16, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }
    var body: some View {
        content
            .padding(padding)
            .modifier(AuraDesignSystem.Blur.glass(cornerRadius))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [AuraDesignSystem.Colors.accent, AuraDesignSystem.Colors.accentSecondary], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .brightness(configuration.isPressed ? -0.1 : 0)
            )
            .foregroundColor(.white)
            .clipShape(Capsule())
            .shadow(color: AuraDesignSystem.Colors.accent.opacity(0.4), radius: 10, x: 0, y: 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var auraPrimary: PrimaryButtonStyle { PrimaryButtonStyle() } }

// Gradient background wrapper
struct GradientBackground<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        ZStack {
            AuraDesignSystem.Gradients.background
                .ignoresSafeArea()
            content()
        }
    }
}
