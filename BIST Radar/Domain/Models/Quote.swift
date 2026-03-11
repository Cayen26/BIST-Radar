// Quote.swift – Real-time / delayed quote
// BIST Radar AI

import Foundation

struct Quote: Identifiable, Codable, Sendable, Hashable {
    var id: String { symbol }
    let symbol: String
    let lastPrice: Double
    let change: Double           // absolute change
    let changePercent: Double    // percent change (e.g. 3.24 = +3.24%)
    let open: Double
    let high: Double
    let low: Double
    let close: Double            // previous close
    let volume: Double           // shares traded
    let volumeTL: Double         // volume in TL
    let marketCap: Double?       // in TL (optional, may be missing)
    let timestamp: Date
    let isDelayed: Bool          // true if data is 15-min delayed

    // MARK: - Convenience
    var isPositive: Bool { changePercent >= 0 }
    var formattedPrice: String { String(format: "%.2f ₺", lastPrice) }
    var formattedChange: String {
        let sign = changePercent >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", changePercent))%"
    }
    var formattedVolume: String {
        let millions = volumeTL / 1_000_000
        if millions >= 1000 { return String(format: "%.1f Mrd ₺", millions / 1000) }
        return String(format: "%.1f Mn ₺", millions)
    }
}

// MARK: - Batch Response DTO
struct QuoteBatchResponse: Codable, Sendable {
    let quotes: [Quote]
    let isDelayed: Bool
    let fetchedAt: Date?
}
