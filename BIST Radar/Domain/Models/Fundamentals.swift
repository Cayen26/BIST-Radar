// Fundamentals.swift – Financial ratios & company info
// BIST Radar AI

import Foundation

struct Fundamentals: Codable, Sendable {
    let symbol: String

    // Valuation
    let peRatio: Double?         // Fiyat/Kazanç
    let pbRatio: Double?         // Piyasa/Defter
    let evEbitda: Double?        // FD/FAVÖK
    let dividendYield: Double?   // Temettü Verimi (%)

    // Size
    let marketCapTL: Double?     // Piyasa Değeri (TL)
    let freefloatPct: Double?    // Halka Açıklık (%)

    // Growth (YoY %)
    let revenueGrowthYoY: Double?
    let netIncomeGrowthYoY: Double?

    // Profitability
    let netMargin: Double?       // Net Kâr Marjı (%)
    let roe: Double?             // Özsermaye Kârlılığı (%)
    let roa: Double?             // Aktif Kârlılığı (%)

    // Balance sheet
    let debtToEquity: Double?
    let currentRatio: Double?

    let updatedAt: Date?
    let isDelayed: Bool

    // MARK: - Formatted helpers
    var formattedPE: String {
        guard let pe = peRatio else { return "—" }
        return String(format: "%.1fx", pe)
    }
    var formattedPB: String {
        guard let pb = pbRatio else { return "—" }
        return String(format: "%.2fx", pb)
    }
    var formattedMarketCap: String {
        guard let mc = marketCapTL else { return "—" }
        let bn = mc / 1_000_000_000
        if bn >= 1000 { return String(format: "%.0f Tr ₺", bn / 1000) }
        return String(format: "%.1f Mn ₺", mc / 1_000_000)
    }
    var formattedDividend: String {
        guard let div = dividendYield else { return "—" }
        return String(format: "%.2f%%", div)
    }
}
