// YahooFinanceProvider.swift – Yahoo Finance canlı veri sağlayıcısı
// BIST Radar AI
//
// ÖNEMLİ: fc.yahoo.com çerezi + crumb mekanizması çalışıyor (finance.yahoo.com DEĞİL)
// BIST hisseleri Yahoo Finance'te ".IS" uzantısıyla bulunur → THYAO.IS, GARAN.IS
// Endeksler: XU100.IS, XU050.IS, XU030.IS
//
// Strateji:
//   1. v7 batch (50 sembol/istek, crumb+çerez) → hızlı, tüm alanlar mevcut
//   2. v8 chart per sembol (crumb yok) → yavaş ama güvenilir, son çare

import Foundation

// MARK: - Oturum ve Crumb Yöneticisi

actor YahooSession {
    static let shared = YahooSession()

    // nonisolated let → actor beklenmeden doğrudan erişilebilir (paralel istekler için)
    nonisolated let session: URLSession

    private var crumb: String?

    private init() {
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = 10
        self.session = URLSession(configuration: config)
    }

    /// Crumb'ı döndürür; gerekirse önce fc.yahoo.com'u ziyaret eder.
    func getCrumb() async -> String? {
        if let c = crumb { return c }
        return await refreshCrumb()
    }

    @discardableResult
    func refreshCrumb() async -> String? {
        // fc.yahoo.com → Yahoo oturumu çerezini alır (finance.yahoo.com değil)
        var fcReq = URLRequest(url: URL(string: "https://fc.yahoo.com/")!)
        fcReq.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        _ = try? await session.data(for: fcReq)

        // Crumb endpoint
        var req = URLRequest(url: URL(string: "https://query1.finance.yahoo.com/v1/test/getcrumb")!)
        req.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: req),
              let val = String(data: data, encoding: .utf8),
              !val.isEmpty, val != "null", !val.contains("Unauthorized"), !val.contains("error")
        else { return nil }

        self.crumb = val
        return val
    }

    func invalidate() { crumb = nil }

    static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
}

// MARK: - Provider

final class YahooFinanceProvider: MarketDataProvider, Sendable {
    var isLive: Bool { true }
    var providerName: String { "Yahoo Finance" }

    // nonisolated let olduğundan await gerekmez → tüm istekler gerçekten paralel çalışır
    private let session: URLSession
    private let fallback = MockMarketProvider()

    init() {
        self.session = YahooSession.shared.session
    }

    // MARK: - Universe & Sectors (bundle JSON)
    func fetchUniverse() async throws -> [CompanyDTO] { try await fallback.fetchUniverse() }
    func fetchSectors()  async throws -> [Sector]     { try await fallback.fetchSectors() }
    func fetchNews(symbol: String?) async throws -> [NewsArticle] { try await fallback.fetchNews(symbol: symbol) }

    // MARK: - Toplu Fiyat – v7 batch (50/istek, paralel)

    func fetchQuotes(symbols: [String]) async throws -> [Quote] {
        guard !symbols.isEmpty else { return [] }

        // Çerezleri kur + crumb al (tek actor hopu, paralel isteklerden önce)
        let crumb = await YahooSession.shared.getCrumb()

        let chunks = symbols.chunkedBatches(of: 50)
        var results: [Quote] = []

        await withTaskGroup(of: [Quote].self) { group in
            for chunk in chunks {
                group.addTask { [self] in
                    await self.fetchChunkSafe(symbols: chunk, crumb: crumb)
                }
            }
            for await batch in group {
                results.append(contentsOf: batch)
            }
        }

        guard !results.isEmpty else {
            throw ProviderError.unknown("Fiyat verisi alınamadı. Lütfen internet bağlantınızı kontrol edip tekrar deneyin.")
        }
        return results
    }

    /// Bir chunk için sırasıyla v7 ve v8 chart stratejilerini dener.
    private func fetchChunkSafe(symbols: [String], crumb: String?) async -> [Quote] {
        let joined = symbols.map { $0 + ".IS" }.joined(separator: ",")
        guard let encSymbols = joined.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }

        // Strateji 1: v7 + crumb (query1) — hızlı, tüm alanlar
        if let crumb,
           let encCrumb = crumb.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://query1.finance.yahoo.com/v7/finance/quote?symbols=\(encSymbols)&crumb=\(encCrumb)&formatted=false"),
           let quotes = await tryV7(url: url),
           !quotes.isEmpty {
            return quotes
        }

        // Strateji 2: v7 crumbsuz (query2) — bazen çalışır
        if let url = URL(string: "https://query2.finance.yahoo.com/v7/finance/quote?symbols=\(encSymbols)&formatted=false"),
           let quotes = await tryV7(url: url),
           !quotes.isEmpty {
            return quotes
        }

        // Strateji 3: v8 chart sembol başına — her zaman çalışır, son çare
        var fallbackQuotes: [Quote] = []
        await withTaskGroup(of: Quote?.self) { group in
            for symbol in symbols {
                group.addTask { [self] in try? await self.fetchSingleViaChart(symbol: symbol) }
            }
            for await q in group { if let q { fallbackQuotes.append(q) } }
        }
        return fallbackQuotes
    }

    private func tryV7(url: URL) async -> [Quote]? {
        var req = URLRequest(url: url)
        req.setValue(YahooSession.ua, forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(YFQuoteResponse.self, from: data)
        else { return nil }
        let quotes = decoded.quoteResponse.result.compactMap(makeQuote)
        return quotes.isEmpty ? nil : quotes
    }

    // MARK: - BIST Endeksleri (v8 chart – crumb gerektirmez)

    func fetchIndices() async throws -> [BISTIndex] {
        let indexMap: [(yahoo: String, symbol: String, name: String)] = [
            ("XU100.IS", "XU100", "BIST 100"),
            ("XU050.IS", "XU050", "BIST 50"),
            ("XU030.IS", "XU030", "BIST 30"),
        ]

        var results: [BISTIndex] = []
        await withTaskGroup(of: BISTIndex?.self) { group in
            for entry in indexMap {
                group.addTask { [self] in
                    guard let url = URL(string: "https://query2.finance.yahoo.com/v8/finance/chart/\(entry.yahoo)?interval=1d&range=5d"),
                          let meta = await self.fetchChartMeta(url: url),
                          let price = meta.regularMarketPrice
                    else { return nil }

                    let prev = meta.chartPreviousClose ?? meta.previousClose ?? price
                    let diff = price - prev
                    let pct  = prev != 0 ? (diff / prev * 100) : 0
                    return BISTIndex(
                        symbol:        entry.symbol,
                        name:          entry.name,
                        value:         price,
                        change:        diff,
                        changePercent: pct,
                        updatedAt:     meta.regularMarketTime.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                    )
                }
            }
            for await idx in group { if let idx { results.append(idx) } }
        }
        return results.sorted { $0.symbol < $1.symbol }
    }

    // MARK: - Mum Grafik (v8 chart)

    func fetchCandles(symbol: String, timeframe: CandleTimeframe, limit: Int) async throws -> [Candle] {
        let (interval, range) = yahooParams(for: timeframe)
        guard let url = URL(string: "https://query2.finance.yahoo.com/v8/finance/chart/\(symbol).IS?interval=\(interval)&range=\(range)") else {
            return []
        }
        var req = URLRequest(url: url)
        req.setValue(YahooSession.ua, forHTTPHeaderField: "User-Agent")
        let data = try await session.data(for: req).0
        let resp = try JSONDecoder().decode(YFChartResponse.self, from: data)

        guard let result    = resp.chart.result?.first,
              let timestamps = result.timestamp,
              let ohlcv      = result.indicators?.quote.first
        else { return [] }

        var candles: [Candle] = []
        for i in timestamps.indices {
            guard i < ohlcv.open.count, i < ohlcv.high.count,
                  i < ohlcv.low.count, i < ohlcv.close.count, i < ohlcv.volume.count,
                  let open  = ohlcv.open[i],  let high  = ohlcv.high[i],
                  let low   = ohlcv.low[i],   let close = ohlcv.close[i]
            else { continue }
            candles.append(Candle(
                timestamp: Date(timeIntervalSince1970: TimeInterval(timestamps[i])),
                open: open, high: high, low: low, close: close,
                volume: Double(ohlcv.volume[i] ?? 0)
            ))
        }
        return Array(candles.suffix(limit))
    }

    // MARK: - Temel Veriler (v10 quoteSummary)

    func fetchFundamentals(symbol: String) async throws -> Fundamentals {
        let modules = "defaultKeyStatistics,financialData,summaryDetail"
        guard let url = URL(string: "https://query2.finance.yahoo.com/v10/finance/quoteSummary/\(symbol).IS?modules=\(modules)") else {
            throw ProviderError.unknown("Geçersiz URL")
        }
        var req = URLRequest(url: url)
        req.setValue(YahooSession.ua, forHTTPHeaderField: "User-Agent")
        let data = try await session.data(for: req).0
        let resp = try JSONDecoder().decode(YFSummaryResponse.self, from: data)
        guard let r = resp.quoteSummary.result?.first else { throw ProviderError.notFound(symbol) }

        let ks = r.defaultKeyStatistics
        let fd = r.financialData
        let sd = r.summaryDetail
        return Fundamentals(
            symbol:             symbol,
            peRatio:            ks?.trailingPE?.raw,
            pbRatio:            ks?.priceToBook?.raw,
            evEbitda:           ks?.enterpriseToEbitda?.raw,
            dividendYield:      sd?.dividendYield?.raw.map { $0 * 100 },
            marketCapTL:        sd?.marketCap?.raw,
            freefloatPct:       nil,
            revenueGrowthYoY:   fd?.revenueGrowth?.raw.map { $0 * 100 },
            netIncomeGrowthYoY: fd?.earningsGrowth?.raw.map { $0 * 100 },
            netMargin:          fd?.netMargins?.raw.map { $0 * 100 },
            roe:                ks?.returnOnEquity?.raw.map { $0 * 100 },
            roa:                ks?.returnOnAssets?.raw.map { $0 * 100 },
            debtToEquity:       fd?.debtToEquity?.raw.map { $0 / 100 },
            currentRatio:       fd?.currentRatio?.raw,
            updatedAt:          Date(),
            isDelayed:          false
        )
    }

    // MARK: - Yardımcılar

    private func fetchSingleViaChart(symbol: String) async throws -> Quote {
        guard let url = URL(string: "https://query2.finance.yahoo.com/v8/finance/chart/\(symbol).IS?interval=1d&range=5d"),
              let meta = await fetchChartMeta(url: url),
              let price = meta.regularMarketPrice
        else { throw ProviderError.notFound(symbol) }

        let prev   = meta.chartPreviousClose ?? meta.previousClose ?? price
        let diff   = price - prev
        let pct    = prev != 0 ? (diff / prev * 100) : 0
        let volume = Double(meta.regularMarketVolume ?? 0)
        return Quote(
            symbol:        symbol,
            lastPrice:     price,
            change:        diff,
            changePercent: pct,
            open:          meta.regularMarketOpen  ?? price,
            high:          meta.regularMarketDayHigh ?? price,
            low:           meta.regularMarketDayLow  ?? price,
            close:         prev,
            volume:        volume,
            volumeTL:      volume * price,
            marketCap:     nil,
            timestamp:     meta.regularMarketTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
            isDelayed:     false
        )
    }

    private func fetchChartMeta(url: URL) async -> YFChartMeta? {
        var req = URLRequest(url: url)
        req.setValue(YahooSession.ua, forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await session.data(for: req),
              let resp = try? JSONDecoder().decode(YFChartResponse.self, from: data)
        else { return nil }
        return resp.chart.result?.first?.meta
    }

    private func makeQuote(_ item: YFQuoteItem) -> Quote? {
        guard let price = item.regularMarketPrice else { return nil }
        let symbol = item.symbol.replacingOccurrences(of: ".IS", with: "")
        let volume = Double(item.regularMarketVolume ?? 0)
        return Quote(
            symbol:        symbol,
            lastPrice:     price,
            change:        item.regularMarketChange ?? 0,
            changePercent: item.regularMarketChangePercent ?? 0,
            open:          item.regularMarketOpen ?? price,
            high:          item.regularMarketDayHigh ?? price,
            low:           item.regularMarketDayLow ?? price,
            close:         item.regularMarketPreviousClose ?? price,
            volume:        volume,
            volumeTL:      volume * price,
            marketCap:     item.marketCap,
            timestamp:     item.regularMarketTime.map { Date(timeIntervalSince1970: TimeInterval($0)) } ?? Date(),
            isDelayed:     false
        )
    }

    private func yahooParams(for tf: CandleTimeframe) -> (interval: String, range: String) {
        switch tf {
        case .oneDay:      return ("5m",  "1d")   // Gerçek intraday – 5 dakikalık mumlar
        case .oneWeek:     return ("1d",  "14d")
        case .oneMonth:    return ("1d",  "1mo")
        case .threeMonths: return ("1d",  "3mo")
        case .oneYear:     return ("1d",  "1y")
        }
    }
}

// MARK: - Array chunking

extension Array {
    func chunkedBatches(of size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Yahoo Finance JSON Modelleri (private)

private struct YFQuoteResponse: Decodable {
    let quoteResponse: YFQuoteResult
}
private struct YFQuoteResult: Decodable {
    let result: [YFQuoteItem]
}
private struct YFQuoteItem: Decodable {
    let symbol:                     String
    let regularMarketPrice:         Double?
    let regularMarketChange:        Double?
    let regularMarketChangePercent: Double?
    let regularMarketOpen:          Double?
    let regularMarketDayHigh:       Double?
    let regularMarketDayLow:        Double?
    let regularMarketPreviousClose: Double?
    let regularMarketVolume:        Int?
    let marketCap:                  Double?
    let regularMarketTime:          Int?
}

private struct YFChartResponse: Decodable {
    let chart: YFChartBody
}
private struct YFChartBody: Decodable {
    let result: [YFChartResult]?
}
private struct YFChartResult: Decodable {
    let meta:       YFChartMeta?
    let timestamp:  [Int]?
    let indicators: YFIndicators?
}
struct YFChartMeta: Decodable {
    let regularMarketPrice:   Double?
    let chartPreviousClose:   Double?
    let previousClose:        Double?
    let regularMarketOpen:    Double?
    let regularMarketDayHigh: Double?
    let regularMarketDayLow:  Double?
    let regularMarketVolume:  Int?
    let regularMarketTime:    Int?
}
private struct YFIndicators: Decodable {
    let quote: [YFOHLCVData]
}
private struct YFOHLCVData: Decodable {
    let open:   [Double?]
    let high:   [Double?]
    let low:    [Double?]
    let close:  [Double?]
    let volume: [Int?]
}

private struct YFSummaryResponse: Decodable {
    let quoteSummary: YFSummaryBody
}
private struct YFSummaryBody: Decodable {
    let result: [YFSummaryResult]?
}
private struct YFSummaryResult: Decodable {
    let defaultKeyStatistics: YFKeyStats?
    let financialData:        YFFinancialData?
    let summaryDetail:        YFSummaryDetail?
}
private struct YFKeyStats: Decodable {
    let trailingPE:         YFRawDouble?
    let priceToBook:        YFRawDouble?
    let enterpriseToEbitda: YFRawDouble?
    let returnOnEquity:     YFRawDouble?
    let returnOnAssets:     YFRawDouble?
}
private struct YFFinancialData: Decodable {
    let currentRatio:   YFRawDouble?
    let debtToEquity:   YFRawDouble?
    let netMargins:     YFRawDouble?
    let revenueGrowth:  YFRawDouble?
    let earningsGrowth: YFRawDouble?
}
private struct YFSummaryDetail: Decodable {
    let dividendYield: YFRawDouble?
    let marketCap:     YFRawDouble?
}
private struct YFRawDouble: Decodable {
    let raw: Double?
}
