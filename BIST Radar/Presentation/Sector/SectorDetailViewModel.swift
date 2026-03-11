// SectorDetailViewModel.swift – Sector detail screen state
// BIST Radar AI

import SwiftUI
import Observation

@Observable
final class SectorDetailViewModel {
    var quotes: [Quote] = []
    var isLoading = false
    var error: String?

    private let quoteRepo: QuoteRepository

    init(quoteRepo: QuoteRepository) {
        self.quoteRepo = quoteRepo
    }

    @MainActor
    func load(symbols: [String]) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            quotes = try await quoteRepo.quotes(for: symbols)
                .sorted { $0.changePercent > $1.changePercent }
        } catch {
            self.error = error.localizedDescription
        }
    }

    func quote(for symbol: String) -> Quote? {
        quotes.first { $0.symbol == symbol }
    }

    var gainers: [Quote] { quotes.filter { $0.changePercent >= 0 } }
    var losers: [Quote]  { quotes.filter { $0.changePercent < 0 } }

    var avgChange: Double {
        guard !quotes.isEmpty else { return 0 }
        return quotes.map(\.changePercent).reduce(0, +) / Double(quotes.count)
    }
}
