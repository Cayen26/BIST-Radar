// Candle.swift – OHLCV candle for charts
// BIST Radar AI

import Foundation

struct Candle: Identifiable, Codable, Sendable {
    var id: Date { timestamp }
    let timestamp: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    let volume: Double

    // MARK: - Derived
    var change: Double { close - open }
    var changePercent: Double { open == 0 ? 0 : (change / open) * 100 }
    var isPositive: Bool { close >= open }
    var midPoint: Double { (high + low) / 2 }
}

enum CandleTimeframe: String, CaseIterable, Sendable {
    case oneDay   = "1G"
    case oneWeek  = "1H"
    case oneMonth = "1A"
    case threeMonths = "3A"
    case oneYear  = "1Y"

    var apiValue: String {
        switch self {
        case .oneDay:      return "1D_5m"  // 5dk intraday – eski günlük cache geçersiz
        case .oneWeek:     return "1W"
        case .oneMonth:    return "1M"
        case .threeMonths: return "3M"
        case .oneYear:     return "1Y"
        }
    }

    var displayName: String { rawValue }

    var candleLimit: Int {
        switch self {
        case .oneDay:      return 200  // 5dk'lık ≈ 96 mum/gün – fazla ver sorun yok
        case .oneWeek:     return 10
        case .oneMonth:    return 22
        case .threeMonths: return 66
        case .oneYear:     return 252
        }
    }
}
