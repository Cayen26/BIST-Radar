// StockDetailViewModel.swift
// BIST Radar AI

import SwiftUI
import Observation

@Observable
final class StockDetailViewModel {
    // MARK: - State
    var quote: Quote?
    var candles: [Candle] = []
    var fundamentals: Fundamentals?
    var insights: [Insight] = []
    var snapshot: IndicatorSnapshot?
    var selectedTimeframe: CandleTimeframe = .oneMonth
    var isLoading = false
    var isLoadingChart = false
    var error: String?

    private let quoteRepo: QuoteRepository
    private let insightEngine: RuleInsightEngine

    init(quoteRepo: QuoteRepository, insightEngine: RuleInsightEngine) {
        self.quoteRepo = quoteRepo
        self.insightEngine = insightEngine
    }

    // MARK: - Load all data
    @MainActor
    func load(symbol: String) async {
        isLoading = true
        defer { isLoading = false }
        error = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.loadQuote(symbol: symbol) }
            group.addTask { await self.loadCandles(symbol: symbol, timeframe: self.selectedTimeframe) }
            group.addTask { await self.loadFundamentals(symbol: symbol) }
        }
    }

    @MainActor
    func loadCandles(symbol: String, timeframe: CandleTimeframe) async {
        isLoadingChart = true
        defer { isLoadingChart = false }
        do {
            let fetched = try await quoteRepo.candles(symbol: symbol, timeframe: timeframe)
            candles = fetched
            computeIndicators(symbol: symbol)
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor
    func changeTimeframe(to tf: CandleTimeframe, symbol: String) async {
        selectedTimeframe = tf
        await loadCandles(symbol: symbol, timeframe: tf)
    }

    // MARK: - Private
    private func loadQuote(symbol: String) async {
        do {
            let q = try await quoteRepo.quote(for: symbol)
            await MainActor.run { self.quote = q }
        } catch {
            await MainActor.run { self.error = error.localizedDescription }
        }
    }

    private func loadFundamentals(symbol: String) async {
        do {
            let f = try await quoteRepo.fundamentals(symbol: symbol)
            await MainActor.run { self.fundamentals = f }
        } catch { }
    }

    private func computeIndicators(symbol: String) {
        guard candles.count >= 15 else { return }
        let snap = insightEngine.buildSnapshot(symbol: symbol, candles: candles)
        snapshot = snap
        insights = insightEngine.generateInsights(snapshot: snap, candles: candles)
    }
}
