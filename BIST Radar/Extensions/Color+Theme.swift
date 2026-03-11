// Color+Theme.swift – Adaptive color palette (dark + light)
// BIST Radar AI

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - UIColor hex helper (private)
private extension UIColor {
    convenience init(hex h: String) {
        let s = h.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let a, r, g, b: UInt64
        switch s.count {
        case 3:  (a,r,g,b) = (255,(v>>8)*17,(v>>4&0xF)*17,(v&0xF)*17)
        case 6:  (a,r,g,b) = (255, v>>16, v>>8 & 0xFF, v & 0xFF)
        case 8:  (a,r,g,b) = (v>>24, v>>16 & 0xFF, v>>8 & 0xFF, v & 0xFF)
        default: (a,r,g,b) = (255,255,255,255)
        }
        self.init(red: CGFloat(r)/255, green: CGFloat(g)/255,
                  blue: CGFloat(b)/255, alpha: CGFloat(a)/255)
    }
}

extension Color {
    // MARK: - Brand (sabit – her iki modda aynı)
    static let brandAccent = Color(hex: "#00C2FF")

    // MARK: - Semantic (sabit)
    static let positive  = Color(hex: "#00D094")
    static let negative  = Color(hex: "#FF4B6E")
    static let neutral   = Color(hex: "#8A8FA8")

    // MARK: - Surfaces (adaptif: karanlık / aydınlık)
    static let surface1 = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#0D0E14")   // derin arka plan (dark)
            : UIColor(hex: "#F2F2F7")   // sistem gri 6 (light)
    })
    static let surface2 = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#15161F")   // kart arka planı (dark)
            : UIColor(hex: "#FFFFFF")   // beyaz kart (light)
    })
    static let surface3 = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#1E2030")   // input / elevated (dark)
            : UIColor(hex: "#EBEBEF")   // hafif gri (light)
    })
    static let surface4 = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#262840")   // hover / pressed (dark)
            : UIColor(hex: "#DCDCE3")   // basılı durum (light)
    })

    // MARK: - Text (adaptif)
    static let textPrimary = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#E8EAF0")
            : UIColor(hex: "#1C1C1E")
    })
    static let textSecondary = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#8A8FA8")
            : UIColor(hex: "#3C3C43").withAlphaComponent(0.6)
    })
    static let textTertiary = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(hex: "#5A5E73")
            : UIColor(hex: "#3C3C43").withAlphaComponent(0.3)
    })

    // MARK: - Sectors
    static let sectorColors: [String: Color] = [
        "Bankacılık":  Color(hex: "#3B82F6"),
        "Enerji":      Color(hex: "#F59E0B"),
        "Teknoloji":   Color(hex: "#8B5CF6"),
        "Sanayi":      Color(hex: "#EC4899"),
        "Perakende":   Color(hex: "#10B981"),
        "Gayrimenkul": Color(hex: "#F97316"),
        "Savunma":     Color(hex: "#EF4444"),
        "Gıda":        Color(hex: "#84CC16"),
        "İletişim":    Color(hex: "#06B6D4"),
        "Ulaşım":      Color(hex: "#6366F1"),
        "Otomotiv":    Color(hex: "#14B8A6"),
        "Madencilik":  Color(hex: "#A16207"),
        "Sigorta":     Color(hex: "#7C3AED"),
        "Holding":     Color(hex: "#475569"),
        "Sağlık":      Color(hex: "#0EA5E9"),
        "Spor":        Color(hex: "#F43F5E"),
        "Turizm":      Color(hex: "#FB923C"),
    ]

    static func sectorColor(for sector: String) -> Color {
        sectorColors[sector] ?? Color(hex: "#8A8FA8")
    }

    // MARK: - Hex initializer (SwiftUI Color)
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:  (a,r,g,b) = (255,(int>>8)*17,(int>>4 & 0xF)*17,(int & 0xF)*17)
        case 6:  (a,r,g,b) = (255, int>>16, int>>8 & 0xFF, int & 0xFF)
        case 8:  (a,r,g,b) = (int>>24, int>>16 & 0xFF, int>>8 & 0xFF, int & 0xFF)
        default: (a,r,g,b) = (1,1,1,0)
        }
        self.init(.sRGB,
                  red:     Double(r) / 255,
                  green:   Double(g) / 255,
                  blue:    Double(b) / 255,
                  opacity: Double(a) / 255)
    }
}

extension ShapeStyle where Self == Color {
    static var positive: Color { .positive }
    static var negative: Color { .negative }
}
