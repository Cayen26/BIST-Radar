// Sector.swift – Sector performance summary
// BIST Radar AI

import Foundation

struct Sector: Identifiable, Codable, Sendable, Hashable {
    var id: String { name }
    let name: String            // "Bankacılık", "Enerji", etc.
    let changePercent: Double   // sector average daily change
    let topGainer: String?      // best performing symbol in sector
    let stockCount: Int
    let updatedAt: Date?

    var isPositive: Bool { changePercent >= 0 }
    var formattedChange: String {
        let sign = changePercent >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", changePercent))%"
    }
}
