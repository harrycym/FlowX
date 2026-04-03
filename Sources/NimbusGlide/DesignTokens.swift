import SwiftUI

// MARK: - Brand Colors

enum NimbusColors {
    static let indigo = Color(red: 0.39, green: 0.40, blue: 0.95)    // #6366F1
    static let violet = Color(red: 0.55, green: 0.36, blue: 0.96)    // #8B5CF6
    static let cyan   = Color(red: 0.02, green: 0.71, blue: 0.83)    // #06B6D4

    // Backgrounds
    static let warmBg     = Color(red: 0.98, green: 0.97, blue: 0.96)  // warm off-white
    static let cardBg     = Color.white
    static let sidebarBg  = Color(red: 0.97, green: 0.96, blue: 0.95)

    // Text
    static let heading    = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let body       = Color(red: 0.40, green: 0.40, blue: 0.45)
    static let muted      = Color(red: 0.60, green: 0.60, blue: 0.64)

    // Status
    static let recording  = Color(red: 0.94, green: 0.27, blue: 0.27)  // warm red
    static let processing = violet
    static let ready      = Color(red: 0.22, green: 0.78, blue: 0.45)  // green
    static let error      = Color(red: 0.94, green: 0.27, blue: 0.27)
}

// MARK: - Brand Gradients

enum NimbusGradients {
    static let primary = LinearGradient(
        colors: [NimbusColors.indigo, NimbusColors.violet],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let full = LinearGradient(
        colors: [NimbusColors.indigo, NimbusColors.violet, NimbusColors.cyan],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let subtle = LinearGradient(
        colors: [NimbusColors.indigo.opacity(0.08), NimbusColors.violet.opacity(0.08)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let banner = LinearGradient(
        colors: [
            Color(red: 0.24, green: 0.25, blue: 0.55),
            Color(red: 0.32, green: 0.22, blue: 0.58)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Spacing & Radii

enum NimbusLayout {
    static let cardRadius: CGFloat = 14
    static let buttonRadius: CGFloat = 24
    static let buttonSmallRadius: CGFloat = 8
    static let sidebarWidth: CGFloat = 220
    static let contentPadding: CGFloat = 32
    static let sheetWidth: CGFloat = 480
    static let emptyStateIconSize: CGFloat = 32

    // Spacing scale
    static let spacing4: CGFloat = 4
    static let spacing6: CGFloat = 6
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing20: CGFloat = 20
    static let spacing24: CGFloat = 24
}

// MARK: - Typography

enum NimbusFonts {
    static let pageTitle: Font = .system(size: 24, weight: .bold)
    static let sectionHeader: Font = .system(size: 16, weight: .semibold)
    static let body: Font = .system(size: 15)
    static let bodyMedium: Font = .system(size: 15, weight: .medium)
    static let caption: Font = .system(size: 13)
    static let small: Font = .system(size: 12)
}

// MARK: - Card Style Modifier

struct NimbusCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(NimbusColors.cardBg)
            .cornerRadius(NimbusLayout.cardRadius)
            .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

extension View {
    func nimbusCard() -> some View {
        modifier(NimbusCard())
    }
}

// MARK: - Hex Color Helper

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
