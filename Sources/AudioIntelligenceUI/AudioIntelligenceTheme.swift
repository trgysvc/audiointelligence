import SwiftUI

/**
 * v6.0: AudioIntelligence UI Design System
 * Adheres to Apple Human Interface Guidelines (HIG) with a premium forensic aesthetic.
 */
public enum AITheme {
    
    // MARK: - Colors
    public enum Colors {
        public static let background = Color(red: 0.04, green: 0.04, blue: 0.04) // Deep Space Black
        public static let accentCyan = Color(red: 0.0, green: 0.9, blue: 1.0)    // Forensic Cyan
        public static let accentOrange = Color(red: 1.0, green: 0.43, blue: 0.0) // High-Trust Orange
        public static let glassWhite = Color.white.opacity(0.1)
        public static let cardBackground = Color.white.opacity(0.05)
        public static let mutedText = Color.gray
    }
    
    // MARK: - Typography (HIG Compliant)
    public enum Typography {
        public static func headline(_ size: CGFloat = 18) -> Font {
            .system(size: size, weight: .bold, design: .rounded)
        }
        
        public static func monoData(_ size: CGFloat = 14) -> Font {
            .system(size: size, weight: .medium, design: .monospaced)
        }
        
        public static func caption(_ size: CGFloat = 12) -> Font {
            .system(size: size, weight: .regular, design: .default)
        }
    }
    
    // MARK: - Shared Styles
    public struct GlassCard: ViewModifier {
        public func body(content: Content) -> some View {
            content
                .background(.ultraThinMaterial)
                .background(Colors.cardBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Colors.glassWhite, lineWidth: 0.5)
                )
        }
    }
}

extension View {
    public func glassCard() -> some View {
        self.modifier(AITheme.GlassCard())
    }
}
