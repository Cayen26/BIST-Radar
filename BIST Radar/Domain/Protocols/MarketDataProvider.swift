// MarketDataProvider.swift – Core data provider protocol
// BIST Radar AI

import Foundation
import Combine

// MARK: - Provider Errors
enum ProviderError: LocalizedError, Sendable {
    case networkUnavailable
    case decodingFailed(String)
    case notFound(String)
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(Int)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .networkUnavailable:        return "İnternet bağlantısı bulunamadı."
        case .decodingFailed(let d):     return "Veri işleme hatası: \(d)"
        case .notFound(let s):           return "\(s) bulunamadı."
        case .rateLimited(let t):
            if let t { return "İstek sınırı aşıldı. \(Int(t))s sonra tekrar deneyin." }
            return "İstek sınırı aşıldı."
        case .serverError(let code):     return "Sunucu hatası: \(code)"
        case .unknown(let m):            return "Bilinmeyen hata: \(m)"
        }
    }
}

// MARK: - Filter / Sort for Stock List
struct StockFilter: Sendable {
    var sector: String?
    var marketSegment: String?
    var indexFilter: IndexFilter?
    var onlyActive: Bool = true

    enum IndexFilter: String, CaseIterable, Sendable {
        case bist30  = "BIST 30"
        case bist50  = "BIST 50"
        case bist100 = "BIST 100"
        case all     = "Tümü"
    }
}

// MARK: - Protocol
protocol MarketDataProvider: Sendable {
    // Universe
    func fetchUniverse() async throws -> [CompanyDTO]

    // Quotes (batch – pass array of symbols)
    func fetchQuotes(symbols: [String]) async throws -> [Quote]

    // Candles / OHLCV
    func fetchCandles(symbol: String, timeframe: CandleTimeframe, limit: Int) async throws -> [Candle]

    // Fundamentals
    func fetchFundamentals(symbol: String) async throws -> Fundamentals

    // Sectors
    func fetchSectors() async throws -> [Sector]

    // BIST Index snapshots
    func fetchIndices() async throws -> [BISTIndex]

    // News feed
    func fetchNews(symbol: String?) async throws -> [NewsArticle]

    // Provider metadata
    var isLive: Bool { get }
    var providerName: String { get }
}

// MARK: - DI Container (simple service locator)
@MainActor
final class AppContainer: ObservableObject {
    static let shared = AppContainer()

    // Active provider (readable from Settings)
    let provider: any MarketDataProvider

    // Repositories
    let universeRepository: UniverseRepository
    let quoteRepository: QuoteRepository
    let watchlistRepository: WatchlistRepository
    let newsRepository: NewsRepository
    let ruleInsightEngine: RuleInsightEngine

    // Assistant (self-configuring: quoteRepository injected at init)
    let assistantEngine: AssistantEngine

    private init() {
        let prov: any MarketDataProvider = YahooFinanceProvider()
        let qRepo = QuoteRepository(provider: prov)
        let iEngine = RuleInsightEngine()

        self.provider            = prov
        self.universeRepository  = UniverseRepository(provider: prov)
        self.quoteRepository     = qRepo
        self.watchlistRepository = WatchlistRepository()
        self.newsRepository      = NewsRepository(provider: prov)
        self.ruleInsightEngine   = iEngine

        let engine = AssistantEngine(
            provider: prov,
            insightEngine: iEngine,
            safetyFilter: SafetyFilter(),
            llmService: LLMService()
        )
        engine.configure(quoteRepository: qRepo)
        self.assistantEngine = engine
    }
}
