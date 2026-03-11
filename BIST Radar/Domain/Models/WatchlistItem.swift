// WatchlistItem.swift – User's favorite stocks (SwiftData)
// BIST Radar AI

import Foundation
import SwiftData

@Model
final class WatchlistItem {
    @Attribute(.unique) var symbol: String
    var companyNameTr: String
    var addedAt: Date
    var sortOrder: Int

    init(symbol: String, companyNameTr: String, sortOrder: Int = 0) {
        self.symbol = symbol
        self.companyNameTr = companyNameTr
        self.addedAt = Date()
        self.sortOrder = sortOrder
    }
}
