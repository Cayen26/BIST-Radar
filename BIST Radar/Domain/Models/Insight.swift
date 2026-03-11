// Insight.swift – Rule-based educational insight
// BIST Radar AI

import Foundation

enum InsightCategory: String, Codable, Sendable {
    case performance  = "Performans"
    case momentum     = "Momentum"
    case volume       = "Hacim"
    case volatility   = "Volatilite"
    case movingAvg    = "Hareketli Ortalama"
    case unusual      = "Olağandışı Hareket"
    case general      = "Genel"
}

enum InsightSeverity: String, Codable, Sendable {
    case info    = "info"
    case warning = "uyarı"
    case neutral = "nötr"
}

struct Insight: Identifiable, Sendable {
    let id: UUID
    let category: InsightCategory
    let severity: InsightSeverity
    let title: String
    let body: String              // educational Turkish text with numeric evidence
    let numericEvidence: String   // e.g. "RSI=68.2, 7g=+12.3%"

    init(
        id: UUID = UUID(),
        category: InsightCategory,
        severity: InsightSeverity = .neutral,
        title: String,
        body: String,
        numericEvidence: String = ""
    ) {
        self.id = id
        self.category = category
        self.severity = severity
        self.title = title
        self.body = body
        self.numericEvidence = numericEvidence
    }
}

// MARK: - Computed indicator snapshot
struct IndicatorSnapshot: Sendable {
    let symbol: String
    let rsi14: Double?
    let sma20: Double?
    let sma50: Double?
    let volatilityScore: Double?    // 0–100
    let volumeAnomalyPct: Double?   // % vs 20d avg
    let change7d: Double?           // %
    let change30d: Double?          // %
    let isUnusualMove: Bool
    let unusualMoveSigma: Double?   // e.g. 2.4σ
    // New indicators
    let ema20: Double?
    let ema50: Double?
    let macd: Double?
    let macdSignal: Double?
    let macdHistogram: Double?
    let bollingerUpper: Double?
    let bollingerMiddle: Double?
    let bollingerLower: Double?
    let bollingerBandwidth: Double?
    let bollingerPercentB: Double?
    let stochRSI: Double?
}
