import SwiftUI

// MARK: - Brand Colors

enum NimbusColors {
    static let indigo = Color(red: 0.39, green: 0.40, blue: 0.95)    // #6366F1
    static let violet = Color(red: 0.55, green: 0.36, blue: 0.96)    // #8B5CF6
    static let cyan   = Color(red: 0.02, green: 0.71, blue: 0.83)    // #06B6D4

    // Backgrounds — adapt to dark mode
    static let warmBg     = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
            : NSColor(red: 0.98, green: 0.97, blue: 0.96, alpha: 1)
    })
    static let cardBg     = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1)
            : NSColor.white
    })
    static let sidebarBg  = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1)
            : NSColor(red: 0.97, green: 0.96, blue: 0.95, alpha: 1)
    })

    // Text — adapt to dark mode
    static let heading    = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1)
            : NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
    })
    static let body       = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.70, green: 0.70, blue: 0.75, alpha: 1)
            : NSColor(red: 0.40, green: 0.40, blue: 0.45, alpha: 1)
    })
    static let muted      = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(red: 0.50, green: 0.50, blue: 0.55, alpha: 1)
            : NSColor(red: 0.60, green: 0.60, blue: 0.64, alpha: 1)
    })

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
    static let sidebarWidth: CGFloat = 190
    static let contentPadding: CGFloat = 24
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
