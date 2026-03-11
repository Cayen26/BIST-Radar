// WatchlistRepository.swift – Watchlist CRUD using SwiftData
// BIST Radar AI

import Foundation
import SwiftData
import Combine

@MainActor
final class WatchlistRepository: ObservableObject {

    func fetchAll(modelContext: ModelContext) -> [WatchlistItem] {
        let descriptor = FetchDescriptor<WatchlistItem>(
            sortBy: [SortDescriptor(\WatchlistItem.sortOrder)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func contains(symbol: String, modelContext: ModelContext) -> Bool {
        fetchAll(modelContext: modelContext).contains { $0.symbol == symbol }
    }

    func add(symbol: String, companyNameTr: String, modelContext: ModelContext) {
        guard !contains(symbol: symbol, modelContext: modelContext) else { return }
        let existing = fetchAll(modelContext: modelContext)
        let item = WatchlistItem(
            symbol: symbol,
            companyNameTr: companyNameTr,
            sortOrder: existing.count
        )
        modelContext.insert(item)
        try? modelContext.save()
    }

    func remove(symbol: String, modelContext: ModelContext) {
        let items = fetchAll(modelContext: modelContext)
        if let item = items.first(where: { $0.symbol == symbol }) {
            modelContext.delete(item)
            try? modelContext.save()
        }
    }

    func toggle(symbol: String, companyNameTr: String, modelContext: ModelContext) {
        if contains(symbol: symbol, modelContext: modelContext) {
            remove(symbol: symbol, modelContext: modelContext)
        } else {
            add(symbol: symbol, companyNameTr: companyNameTr, modelContext: modelContext)
        }
    }
}
