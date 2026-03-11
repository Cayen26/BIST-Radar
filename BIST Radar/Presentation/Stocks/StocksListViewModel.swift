// StocksListViewModel.swift
// BIST Radar AI

import SwiftUI
import SwiftData
import Observation

@Observable
final class StocksListViewModel {
    // MARK: - Search & Filter state
    var searchText: String = ""
    var filter = StockFilter()
    var sortOption: SortOption = .symbol
    var isLoading = false

    // MARK: - Sort options
    enum SortOption: String, CaseIterable {
        case symbol      = "Sembol"
        case nameAZ      = "Ad (A-Z)"
        case changeAsc   = "Değişim ↑"
        case changeDesc  = "Değişim ↓"
        case volumeDesc  = "Hacim ↓"
    }

    // MARK: - Quotes cache (for sorting/display)
    var quotesBySymbol: [String: Quote] = [:]
    private let quoteRepo: QuoteRepository

    init(quoteRepo: QuoteRepository) {
        self.quoteRepo = quoteRepo
    }

    // MARK: - Filtered + sorted companies
    func filtered(companies: [Company]) -> [Company] {
        // 1. Filtre koşulları (aktiflik, sektör, endeks, pazar)
        let pool = companies.filter { company in
            guard company.isActive else { return !filter.onlyActive }
            if let sector = filter.sector, !sector.isEmpty {
                guard company.sector == sector else { return false }
            }
            if let segment = filter.marketSegment, !segment.isEmpty {
                guard company.marketSegment == segment else { return false }
            }
            if let index = filter.indexFilter {
                switch index {
                case .bist30:  guard company.inBIST30  else { return false }
                case .bist50:  guard company.inBIST50  else { return false }
                case .bist100: guard company.inBIST100 else { return false }
                case .all:     break
                }
            }
            return true
        }

        // 2. Fuzzy arama (boşsa tüm havuz döner)
        var result = searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? pool
            : FuzzySearch.filter(pool, query: searchText)

        // 3. Sıralama
        switch sortOption {
        case .symbol:
            result.sort { $0.symbol < $1.symbol }
        case .nameAZ:
            result.sort { $0.companyNameTr < $1.companyNameTr }
        case .changeDesc:
            result.sort { (quotesBySymbol[$0.symbol]?.changePercent ?? 0) > (quotesBySymbol[$1.symbol]?.changePercent ?? 0) }
        case .changeAsc:
            result.sort { (quotesBySymbol[$0.symbol]?.changePercent ?? 0) < (quotesBySymbol[$1.symbol]?.changePercent ?? 0) }
        case .volumeDesc:
            result.sort { (quotesBySymbol[$0.symbol]?.volumeTL ?? 0) > (quotesBySymbol[$1.symbol]?.volumeTL ?? 0) }
        }

        return result
    }

    // MARK: - Load quotes for visible symbols
    func loadQuotes(for symbols: [String]) async {
        guard !symbols.isEmpty else { return }
        do {
            let quotes = try await quoteRepo.quotes(for: symbols)
            await MainActor.run {
                for q in quotes { quotesBySymbol[q.symbol] = q }
            }
        } catch { }
    }

    func resetFilter() {
        filter = StockFilter()
        sortOption = .symbol
        searchText = ""
    }
}
