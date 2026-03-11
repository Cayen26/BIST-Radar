// LiveMarketProvider.swift – Real API integration (placeholder endpoints)
// BIST Radar AI
//
// TO SWITCH FROM MOCK → LIVE:
//   1. In AppContainer (MarketDataProvider.swift), change:
//      let provider: any MarketDataProvider = MockMarketProvider()
//      → let provider: any MarketDataProvider = LiveMarketProvider()
//   2. Set API base URL in NetworkClient.swift (baseURL property)
//   3. Add API key to Keychain (NOT hardcoded) using KeychainHelper.
//   4. Replace placeholder endpoint paths below with real paths.

import Foundation

final class LiveMarketProvider: MarketDataProvider, Sendable {
    var isLive: Bool { true }
    var providerName: String { "Live API" }

    private let client = NetworkClient.shared
    private let apiKey: String

    init() {
        // API key must come from Keychain — NEVER hardcode
        self.apiKey = KeychainHelper.readAPIKey() ?? ""
    }

    // MARK: - Universe
    // GET /universe
    func fetchUniverse() async throws -> [CompanyDTO] {
        try await client.request(
            APIRequest(path: "/universe",
                       headers: authHeader()),
            as: UniverseResponse.self
        ).companies
    }

    // MARK: - Batch Quotes
    // POST /quotes  { "symbols": ["THYAO","GARAN",...] }
    func fetchQuotes(symbols: [String]) async throws -> [Quote] {
        // Chunk into batches of 50 for API compliance
        let chunks = symbols.chunked(into: 50)
        var results: [Quote] = []
        await withTaskGroup(of: [Quote].self) { group in
            for chunk in chunks {
                group.addTask {
                    let body = try? JSONEncoder().encode(["symbols": chunk])
                    let req  = APIRequest(path: "/quotes", method: .POST, body: body, headers: self.authHeader())
                    let resp = try? await self.client.request(req, as: QuoteBatchResponse.self)
                    return resp?.quotes ?? []
                }
            }
            for await batch in group { results.append(contentsOf: batch) }
        }
        return results
    }

    // MARK: - Candles
    // GET /candles?symbol=THYAO&tf=1D&limit=200
    func fetchCandles(symbol: String, timeframe: CandleTimeframe, limit: Int) async throws -> [Candle] {
        try await client.request(
            APIRequest(
                path: "/candles",
                queryItems: [
                    URLQueryItem(name: "symbol", value: symbol),
                    URLQueryItem(name: "tf", value: timeframe.apiValue),
                    URLQueryItem(name: "limit", value: "\(limit)"),
                ],
                headers: authHeader()
            ),
            as: CandleResponse.self
        ).candles
    }

    // MARK: - Fundamentals
    // GET /fundamentals?symbol=THYAO
    func fetchFundamentals(symbol: String) async throws -> Fundamentals {
        try await client.request(
            APIRequest(
                path: "/fundamentals",
                queryItems: [URLQueryItem(name: "symbol", value: symbol)],
                headers: authHeader()
            ),
            as: Fundamentals.self
        )
    }

    // MARK: - Sectors
    // GET /sectors
    func fetchSectors() async throws -> [Sector] {
        try await client.request(
            APIRequest(path: "/sectors", headers: authHeader()),
            as: SectorResponse.self
        ).sectors
    }

    // MARK: - BIST Indices
    // GET /indices
    func fetchIndices() async throws -> [BISTIndex] {
        try await client.request(
            APIRequest(path: "/indices", headers: authHeader()),
            as: IndexResponse.self
        ).indices
    }

    // MARK: - News
    // GET /news?symbol=THYAO
    func fetchNews(symbol: String?) async throws -> [NewsArticle] {
        var items: [URLQueryItem] = []
        if let sym = symbol { items.append(URLQueryItem(name: "symbol", value: sym)) }
        return try await client.request(
            APIRequest(path: "/news", queryItems: items, headers: authHeader()),
            as: NewsResponse.self
        ).articles
    }

    // MARK: - Helpers
    private func authHeader() -> [String: String] {
        guard !apiKey.isEmpty else { return [:] }
        return ["Authorization": "Bearer \(apiKey)"]
    }
}

// MARK: - Response wrappers
private struct UniverseResponse: Codable {
    let companies: [CompanyDTO]
}

private struct CandleResponse: Codable {
    let candles: [Candle]
}

private struct SectorResponse: Codable {
    let sectors: [Sector]
}

private struct IndexResponse: Codable {
    let indices: [BISTIndex]
}

private struct NewsResponse: Codable {
    let articles: [NewsArticle]
}

// MARK: - Array chunking
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Keychain helper (stub)
enum KeychainHelper {
    static func readAPIKey() -> String? {
        // TODO: implement Keychain read for "com.bistradai.apikey"
        // Use Security framework: SecItemCopyMatching
        return nil
    }

    static func saveAPIKey(_ key: String) {
        // TODO: implement Keychain write
    }
}
