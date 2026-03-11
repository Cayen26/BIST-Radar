// BISTIndex.swift – BIST major index snapshot
// BIST Radar AI

import Foundation

struct BISTIndex: Identifiable, Codable, Sendable {
    var id: String { symbol }
    let symbol: String        // "XU100", "XU050", "XU030"
    let name: String          // "BIST 100", "BIST 50", "BIST 30"
    let value: Double
    let change: Double
    let changePercent: Double
    let updatedAt: Date?

    var isPositive: Bool { changePercent >= 0 }

    var formattedValue: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 2
        f.groupingSeparator = "."
        f.decimalSeparator = ","
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    var formattedChange: String {
        let sign = changePercent >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.2f", changePercent))%"
    }
}
