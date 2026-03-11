// QuoteRepository.swift – Quote fetching with memory + disk cache
// BIST Radar AI

import Foundation
import Combine

@MainActor
final class QuoteRepository: ObservableObject {
    private let provider: any MarketDataProvider

    init(provider: any MarketDataProvider) {
        self.provider = provider
    }

    // MARK: - Fetch single quote
    func quote(for symbol: String) async throws -> Quote {
        // Memory cache hit
        if let cached = AppCaches.quotes.value(forKey: symbol) {
            return cached
        }
        let quotes = try await provider.fetchQuotes(symbols: [symbol])
        if let q = quotes.first {
            AppCaches.quotes.set(q, forKey: symbol, ttl: AppCaches.quoteTTL)
            return q
        }
        throw ProviderError.notFound(symbol)
    }

    // MARK: - Batch fetch (performance: up to 600 symbols)
    func quotes(for symbols: [String]) async throws -> [Quote] {
        var results: [Quote] = []
        var missing: [String] = []

        // Serve from memory cache
        for symbol in symbols {
            if let cached = AppCaches.quotes.value(forKey: symbol) {
                results.append(cached)
            } else {
                missing.append(symbol)
            }
        }

        if missing.isEmpty { return results }

        // Fetch missing from provider
        let fetched = try await provider.fetchQuotes(symbols: missing)
        for q in fetched {
            AppCaches.quotes.set(q, forKey: q.symbol, ttl: AppCaches.quoteTTL)
            results.append(q)
        }
        return results
    }

    // MARK: - Candles with disk + memory cache
    func candles(symbol: String, timeframe: CandleTimeframe) async throws -> [Candle] {
        let key = "candles_\(symbol)_\(timeframe.apiValue)"
        let ttl = AppCaches.candleTTL(for: timeframe)

        // Memory cache
        if let mem = AppCaches.candles.value(forKey: key) {
            return mem
        }

        // Disk cache (sadece uzun vadeli timeframe'ler için; intraday her zaman taze çek)
        if timeframe != .oneDay,
           let disk = await DiskCache.shared.read(key: key, as: [Candle].self) {
            AppCaches.candles.set(disk, forKey: key, ttl: ttl)
            return disk
        }

        // Fetch
        let candles = try await provider.fetchCandles(
            symbol: symbol,
            timeframe: timeframe,
            limit: timeframe.candleLimit + 60 // extra for indicator warmup
        )

        AppCaches.candles.set(candles, forKey: key, ttl: ttl)
        await DiskCache.shared.write(candles, key: key, ttl: ttl)
        return candles
    }

    // MARK: - Fundamentals
    func fundamentals(symbol: String) async throws -> Fundamentals {
        let key = "funda_\(symbol)"

        if let mem = AppCaches.fundas.value(forKey: symbol) {
            return mem
        }
        if let disk = await DiskCache.shared.read(key: key, as: Fundamentals.self) {
            AppCaches.fundas.set(disk, forKey: symbol, ttl: AppCaches.fundaTTL)
            return disk
        }

        let funda = try await provider.fetchFundamentals(symbol: symbol)
        AppCaches.fundas.set(funda, forKey: symbol, ttl: AppCaches.fundaTTL)
        await DiskCache.shared.write(funda, key: key, ttl: AppCaches.fundaTTL)
        return funda
    }

    // MARK: - Sectors
    func sectors() async throws -> [Sector] {
        let cacheKey = "sectors_all"
        if let mem = AppCaches.sectors.value(forKey: cacheKey) {
            return mem
        }
        let s = try await provider.fetchSectors()
        AppCaches.sectors.set(s, forKey: cacheKey, ttl: AppCaches.sectorTTL)
        return s
    }

    // MARK: - BIST Indices
    func indices() async throws -> [BISTIndex] {
        let cacheKey = "indices_all"
        if let mem = AppCaches.indices.value(forKey: cacheKey) {
            return mem
        }
        let idx = try await provider.fetchIndices()
        AppCaches.indices.set(idx, forKey: cacheKey, ttl: AppCaches.sectorTTL)
        return idx
    }

    func invalidateCache(for symbol: String) {
        AppCaches.quotes.removeValue(forKey: symbol)
        AppCaches.fundas.removeValue(forKey: symbol)
    }
}
