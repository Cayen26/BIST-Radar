// DashboardViewModel.swift
// BIST Radar AI

import SwiftUI
import Observation

@Observable
final class DashboardViewModel {
    // MARK: - State
    var topGainers: [Quote] = []
    var topLosers: [Quote] = []
    var volumeSpikes: [Quote] = []
    var sectors: [Sector] = []
    var bistIndices: [BISTIndex] = []
    var isLoading = false
    var error: String?
    var lastUpdated: Date?

    private let quoteRepo: QuoteRepository
    private let universeSymbols: () -> [String]

    init(quoteRepo: QuoteRepository, universeSymbols: @escaping () -> [String]) {
        self.quoteRepo = quoteRepo
        self.universeSymbols = universeSymbols
    }

    // MARK: - Load
    @MainActor
    func load(allSymbols: [String]) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil

        // Her task bağımsız: biri hata verse diğerleri etkilenmez
        async let sectorsTask = quoteRepo.sectors()
        async let indicesTask = quoteRepo.indices()
        async let quotesTask  = quoteRepo.quotes(for: allSymbols)

        if let fetchedSectors = try? await sectorsTask {
            sectors = fetchedSectors.sorted { abs($0.changePercent) > abs($1.changePercent) }
        }

        if let fetchedIndices = try? await indicesTask {
            bistIndices = fetchedIndices
        }

        if let allQuotes = try? await quotesTask {
            let sorted   = allQuotes.sorted { $0.changePercent > $1.changePercent }
            topGainers   = Array(sorted.prefix(10))
            topLosers    = Array(sorted.suffix(10).reversed())
            volumeSpikes = allQuotes.sorted { $0.volumeTL > $1.volumeTL }.prefix(10).map { $0 }
        } else {
            error = "Fiyatlar yüklenemedi. Yenilemek için aşağı kaydırın."
        }

        lastUpdated = Date()
    }
}
