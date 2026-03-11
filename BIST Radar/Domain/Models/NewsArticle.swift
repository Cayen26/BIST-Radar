// NewsArticle.swift – Financial news item model
// BIST Radar AI

import Foundation

struct NewsArticle: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let summary: String
    let source: String
    let category: NewsCategory
    let relatedSymbols: [String]
    let publishedAt: Date
    let isBreaking: Bool

    var timeAgo: String {
        let seconds = max(0, Date().timeIntervalSince(publishedAt))
        if seconds < 60    { return "Az önce" }
        if seconds < 3600  { return "\(Int(seconds / 60)) dk önce" }
        if seconds < 86400 { return "\(Int(seconds / 3600)) saat önce" }
        return "\(Int(seconds / 86400)) gün önce"
    }
}

// Raw values = JSON coding keys (English case names)
enum NewsCategory: String, Codable, Sendable, CaseIterable {
    case kapDisclosure  = "kapDisclosure"
    case market         = "market"
    case economy        = "economy"
    case sector         = "sector"
    case world          = "world"

    /// Turkish display label shown in the UI
    var displayName: String {
        switch self {
        case .kapDisclosure: return "KAP Bildirimi"
        case .market:        return "Genel Piyasa"
        case .economy:       return "Ekonomi"
        case .sector:        return "Sektör"
        case .world:         return "Dünya"
        }
    }

    var icon: String {
        switch self {
        case .kapDisclosure: return "doc.text.fill"
        case .market:        return "chart.xyaxis.line"
        case .economy:       return "banknote"
        case .sector:        return "chart.bar.fill"
        case .world:         return "globe"
        }
    }

    var color: String {
        switch self {
        case .kapDisclosure: return "#F59E0B"
        case .market:        return "#6366F1"
        case .economy:       return "#10B981"
        case .sector:        return "#3B82F6"
        case .world:         return "#8B5CF6"
        }
    }
}
