// MockMarketProvider.swift – Offline demo with bundled JSON
// BIST Radar AI

import Foundation

final class MockMarketProvider: MarketDataProvider, Sendable {
    var isLive: Bool { false }
    var providerName: String { "Mock (Demo)" }

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Universe
    func fetchUniverse() async throws -> [CompanyDTO] {
        try await simulateDelay()
        return try loadBundled([CompanyDTO].self, resource: "universe")
    }

    // MARK: - Quotes
    func fetchQuotes(symbols: [String]) async throws -> [Quote] {
        try await simulateDelay()
        let all = try loadBundled([Quote].self, resource: "quotes")
        if symbols.isEmpty { return all }
        return all.filter { symbols.contains($0.symbol) }
    }

    // MARK: - Candles
    func fetchCandles(symbol: String, timeframe: CandleTimeframe, limit: Int) async throws -> [Candle] {
        try await simulateDelay(ms: 200)
        let key = "candles_\(symbol.uppercased())"
        // Try symbol-specific file first, fallback to generic
        if let candles = try? loadBundled([Candle].self, resource: key) {
            return Array(candles.suffix(limit))
        }
        let all = try loadBundled([Candle].self, resource: "candles")
        return Array(all.suffix(limit))
    }

    // MARK: - Fundamentals
    func fetchFundamentals(symbol: String) async throws -> Fundamentals {
        try await simulateDelay()
        let all = try loadBundled([Fundamentals].self, resource: "fundamentals")
        return all.first { $0.symbol == symbol } ?? mockFundamentals(symbol: symbol)
    }

    // MARK: - Sectors
    func fetchSectors() async throws -> [Sector] {
        try await simulateDelay()
        return try loadBundled([Sector].self, resource: "sectors")
    }

    // MARK: - BIST Indices
    func fetchIndices() async throws -> [BISTIndex] {
        try await simulateDelay(ms: 200)
        return try loadBundled([BISTIndex].self, resource: "indices")
    }

    // MARK: - News
    func fetchNews(symbol: String?) async throws -> [NewsArticle] {
        try await simulateDelay(ms: 250)
        let all = try loadBundled([NewsArticle].self, resource: "news")
        guard let sym = symbol, !sym.isEmpty else { return all }
        return all.filter { $0.relatedSymbols.contains(sym) }
    }

    // MARK: - Helpers
    private func loadBundled<T: Decodable>(_ type: T.Type, resource: String) throws -> T {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "json") else {
            throw ProviderError.notFound("Bundle resource: \(resource).json")
        }
        let data = try Data(contentsOf: url)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ProviderError.decodingFailed("\(resource): \(error.localizedDescription)")
        }
    }

    private func simulateDelay(ms: UInt64 = 400) async throws {
        // Simulate realistic network latency in demo mode
        try await Task.sleep(nanoseconds: ms * 1_000_000)
    }

    private func mockFundamentals(symbol: String) -> Fundamentals {
        Fundamentals(
            symbol: symbol,
            peRatio: Double.random(in: 8...25),
            pbRatio: Double.random(in: 0.8...4.0),
            evEbitda: Double.random(in: 5...15),
            dividendYield: Double.random(in: 0...8),
            marketCapTL: Double.random(in: 1e9...100e9),
            freefloatPct: Double.random(in: 15...65),
            revenueGrowthYoY: Double.random(in: -10...60),
            netIncomeGrowthYoY: Double.random(in: -20...80),
            netMargin: Double.random(in: 2...30),
            roe: Double.random(in: 5...40),
            roa: Double.random(in: 2...20),
            debtToEquity: Double.random(in: 0.2...3.0),
            currentRatio: Double.random(in: 0.8...3.0),
            updatedAt: Date(),
            isDelayed: true
        )
    }
}
