import SwiftUI

enum WhetstoneTheme {
    // Palette
    static let obsidian  = Color(hex: "07090d")
    static let blade     = Color(hex: "4ea3ff")  // steel-blue — primary accent
    static let ember     = Color(hex: "ff7a1a")  // hot ember — reserved for spark/caret/gauge tip
    /// Faint green rim around live camera PiP — signals “tap to capture”.
    static let pipPreviewOutline = Color(red: 0.35, green: 0.78, blue: 0.48).opacity(0.55)

    // Surface tints
    static let surface   = Color(hex: "0d1017")
    static let surfaceHigh = Color(hex: "141920")

    // Dimensions
    static let chamferSize: CGFloat  = 14   // user-message corner bevel
    static let bladeEdgeWidth: CGFloat = 2
    static let sparkDotSize: CGFloat   = 7

    // Assumed model context window (tokens) — used for gauge %
    static let contextWindowTokens: Int = 131_072  // llama-4-scout 128k
}

// MARK: - Shapes

struct ChamferedTopRight: Shape {
    var chamfer: CGFloat = WhetstoneTheme.chamferSize

    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - chamfer, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + chamfer))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: - Color helper

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
