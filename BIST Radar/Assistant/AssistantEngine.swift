// AssistantEngine.swift – Orchestrates context + LLM/rules + safety filter
// BIST Radar AI

import Foundation
import Combine

@MainActor
final class AssistantEngine: ObservableObject {
    private let provider: any MarketDataProvider
    private let insightEngine: RuleInsightEngine
    private let safetyFilter: SafetyFilter
    private let llmService: LLMService
    private var contextBuilder: ContextBuilder?
    private var quoteRepository: QuoteRepository?

    @Published var isProcessing = false

    // MARK: - Company catalog (loaded once from provider)
    private struct CompanyEntry: Sendable {
        let symbol: String
        let symbolNorm: String      // lowercase normalized (e.g. "thyao")
        let nameNorm: String        // e.g. "turk hava yollari"
        let shortNameNorm: String   // e.g. "thy"
    }
    private var companyCatalog: [CompanyEntry] = []

    init(
        provider: any MarketDataProvider,
        insightEngine: RuleInsightEngine,
        safetyFilter: SafetyFilter,
        llmService: LLMService
    ) {
        self.provider = provider
        self.insightEngine = insightEngine
        self.safetyFilter = safetyFilter
        self.llmService = llmService
    }

    func configure(quoteRepository: QuoteRepository) {
        self.quoteRepository = quoteRepository
        self.contextBuilder = ContextBuilder(
            quoteRepository: quoteRepository,
            insightEngine: insightEngine
        )
        // Load company catalog in background for symbol resolution
        Task { await loadCompanyCatalog() }
    }

    private func loadCompanyCatalog() async {
        guard let dtos = try? await provider.fetchUniverse() else { return }
        companyCatalog = dtos.map {
            CompanyEntry(
                symbol: $0.symbol,
                symbolNorm: $0.symbol.turkishNormalized(),
                nameNorm: $0.companyNameTr.turkishNormalized(),
                shortNameNorm: $0.shortName.turkishNormalized()
            )
        }
    }

    // MARK: - Main entry point
    func respond(
        to query: String,
        contextSymbol: String?,
        conversationHistory: [AnthropicMessage] = []
    ) async -> String {
        isProcessing = true
        defer { isProcessing = false }

        // Katalog henüz yüklenmediyse bekle (ilk mesaj senaryosu)
        if companyCatalog.isEmpty { await loadCompanyCatalog() }

        // Try to extract a stock symbol from the query itself
        let resolvedSymbol = contextSymbol ?? extractSymbol(from: query)

        let context = await contextBuilder?.build(symbol: resolvedSymbol)
            ?? AssistantContext(symbol: nil, quote: nil, candles: [], fundamentals: nil,
                                snapshot: nil, insights: [], fetchedAt: Date())

        // Sector-specific async query (needs live sector data)
        if let sectorResp = await handleSectorQuery(query: query) {
            return safetyFilter.filter(sectorResp)
        }

        // Chip / eğitsel sorular → anlık built-in cevap
        if let builtIn = handleBuiltInQuery(query: query, context: context) {
            return safetyFilter.filter(builtIn)
        }

        // Serbest sohbet, hisse analizi → LLM
        if llmService.isEnabled {
            do {
                let contextText = context.richTextSummary
                let userPrompt = PromptTemplates.userPrompt(query: query, contextData: contextText)

                var messages = conversationHistory
                messages.append(AnthropicMessage(role: "user", content: userPrompt))

                let llmRaw = try await llmService.generate(
                    messages: messages,
                    systemPrompt: PromptTemplates.systemPrompt
                )
                return safetyFilter.filter(llmRaw)
            } catch { }
        }

        return ruleBasedResponse(query: query, context: context)
    }

    // MARK: - Streaming entry point
    func respondStream(
        to query: String,
        contextSymbol: String?,
        conversationHistory: [AnthropicMessage] = []
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                self.isProcessing = true
                defer { self.isProcessing = false }

                if self.companyCatalog.isEmpty { await self.loadCompanyCatalog() }
                let resolvedSymbol = contextSymbol ?? self.extractSymbol(from: query)
                let context = await self.contextBuilder?.build(symbol: resolvedSymbol)
                    ?? AssistantContext(symbol: nil, quote: nil, candles: [], fundamentals: nil,
                                       snapshot: nil, insights: [], fetchedAt: Date())

                // Sektör sorgusu (anlık veri gerektirir)
                if let sectorResp = await self.handleSectorQuery(query: query) {
                    continuation.yield(self.safetyFilter.filter(sectorResp))
                    continuation.finish()
                    return
                }

                // Chip / eğitsel sorular → anlık built-in cevap
                if let builtIn = self.handleBuiltInQuery(query: query, context: context) {
                    continuation.yield(self.safetyFilter.filter(builtIn))
                    continuation.finish()
                    return
                }

                // Serbest sohbet → LLM streaming
                if self.llmService.isEnabled {
                    let contextText = context.richTextSummary
                    let userPrompt = PromptTemplates.userPrompt(query: query, contextData: contextText)
                    var messages = conversationHistory
                    messages.append(AnthropicMessage(role: "user", content: userPrompt))

                    do {
                        for try await token in self.llmService.generateStream(
                            messages: messages,
                            systemPrompt: PromptTemplates.systemPrompt
                        ) {
                            continuation.yield(token)
                        }
                        continuation.finish()
                        return
                    } catch { }
                }

                // Fallback
                let fallback = self.ruleBasedResponse(query: query, context: context)
                continuation.yield(self.safetyFilter.filter(fallback))
                continuation.finish()
            }
        }
    }

    // MARK: - Symbol extraction from free text

    private static let stopWords: Set<String> = [
        // Türkçe yaygın kelimeler
        "ne", "bu", "bir", "var", "yok", "mi", "mu", "mi", "mu",
        "ile", "ve", "de", "da", "ki", "su", "o", "ya", "ya",
        "nasil", "nedir", "neden", "nasil", "analiz", "hisse",
        "borsa", "bist", "piyasa", "fiyat", "durum", "neler",
        "son", "gunluk", "guncel", "bugun", "hakkinda",
        "icin", "stock", "share", "grafik", "teknik",
        "nedir", "nasil", "acikla", "anlat", "yorumla",
        "fark", "farki", "neden", "onemli", "onem",
        "genel", "ozet", "ozeti", "bilgi", "kavram",
        "strateji", "strateji", "egitim", "egitsel",
        // Teknik analiz kısaltmaları (hisse sanılmasın)
        "rsi", "macd", "ema", "sma", "atr", "obv", "cci",
        "stoch", "stochrsi", "adx", "sar", "vwap", "twap",
        "bb", "kc", "dc", "ichimoku",
        // Temel analiz kısaltmaları
        "roe", "roa", "eps", "dps", "bvps", "fcf", "ebitda",
        "ev", "pe", "pb", "ps", "peg", "dca", "ipo", "spac",
        "pd", "dd", "fk",
        // Pivot seviyeleri
        "pp", "r1", "r2", "r3", "s1", "s2", "s3",
        // Genel finans terimleri
        "golden", "death", "cross", "bollinger", "fibonacci",
        "pivot", "swing", "trend", "momentum", "volatilite",
        "hacim", "volume", "bandwidth", "percentb", "histogram",
        "signal", "sinyal", "long", "short", "stop", "loss",
        "trailing", "risk", "getiri", "portfoy", "lot",
        "temettü", "temettu", "dividend", "faiz", "enflasyon",
        "dovizkuru", "kurlar", "dolar", "euro",
    ]

    private func extractSymbol(from query: String) -> String? {
        // FuzzySearch.resolve ile tüm eşleme mantığı merkezi yerden çalışır
        let catalog = companyCatalog.map {
            FuzzySearch.ResolveEntry(
                symbol: $0.symbol,
                symbolNorm: $0.symbolNorm,
                nameNorm: $0.nameNorm,
                shortNameNorm: $0.shortNameNorm
            )
        }

        if let resolved = FuzzySearch.resolve(query: query, catalog: catalog, stopWords: Self.stopWords) {
            return resolved
        }

        // Fallback: büyük harf sembol pattern (katalog boşsa)
        // Min 4 harf — RSI/EMA/ROE gibi 2-3 harfli finans kısaltmalarını eliyor
        let symbolPattern = try? NSRegularExpression(pattern: "^[A-ZÇŞİÖÜ]{4,6}$")
        for word in query.components(separatedBy: .whitespacesAndNewlines) {
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            let cleanNorm = clean.turkishNormalized()
            guard clean.count >= 4, !Self.stopWords.contains(cleanNorm) else { continue }
            let range = NSRange(clean.startIndex..., in: clean)
            if symbolPattern?.firstMatch(in: clean, range: range) != nil { return clean }
        }

        return nil
    }

    // MARK: - Built-in Q&A (keyword matching)
    private func handleBuiltInQuery(query: String, context: AssistantContext) -> String? {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // --- Eğitim sorularına yanıt ---
        if q.contains("rsi nedir") || q.contains("rsi göstergesi") || q == "rsi" ||
           q.contains("relative strength") {
            return rsiExplain()
        }
        if q.contains("macd nedir") || q == "macd" || q.contains("macd göstergesi") {
            return macdExplain()
        }
        if q.contains("bollinger") {
            return bollingerExplain()
        }
        if q.contains("fibonacci") {
            return fibonacciExplain()
        }
        if q.contains("stokastik") || q.contains("stochastic") {
            return stochasticExplain()
        }
        if q.contains("atr nedir") || q == "atr" || q.contains("average true range") ||
           q.contains("ortalama gerçek aralık") {
            return atrExplain()
        }
        if q.contains("obv nedir") || q == "obv" || q.contains("on balance volume") {
            return obvExplain()
        }
        if q.contains("hareketli ortalama") || q.contains("moving average") ||
           q.contains("ma20") || q.contains("ma50") || q.contains("sma nedir") ||
           q.contains("ema nedir") || q.contains("üstel ortalama") {
            return maExplain()
        }
        if (q.contains("hacim") || q.contains("volume")) &&
           (q.contains("nedir") || q.contains("ne anlam") || q.contains("açıkla") || q.contains("önemli")) {
            return volumeExplain()
        }
        if q.contains("volatilite") || q.contains("oynaklık") {
            return volatilityExplain()
        }
        if q.contains("beta") && (q.contains("nedir") || q.contains("katsayı") || q.contains("ne demek")) {
            return betaExplain()
        }
        if q.contains("f/k") || (q.contains("pe") && q.contains("nedir")) ||
           q.contains("fiyat kazanç") || q.contains("fiyat/kazanç") {
            return peExplain()
        }
        if q.contains("pd/dd") || q.contains("pb oranı") || q.contains("piyasa defter") {
            return pbExplain()
        }
        if q.contains("temettü") || q.contains("dividend") {
            return dividendExplain()
        }
        if q.contains("destek") || q.contains("direnç") || q.contains("support") || q.contains("resistance") {
            // Eğer bağlamda hisse varsa → hisseye özel destek/direnç
            if let sym = context.symbol, context.hasData, !context.candles.isEmpty {
                return supportResistanceAnalysis(sym: sym, context: context)
            }
            // Yoksa eğitsel açıklama
            return supportResistanceExplain()
        }
        if q.contains("trend") && (q.contains("nedir") || q.contains("analiz") || q.contains("ne demek")) {
            return trendExplain()
        }
        if q.contains("piyasa değeri") || q.contains("market cap") || q.contains("halka açık") {
            return marketCapExplain()
        }
        if q.contains("teknik analiz nedir") || q.contains("teknik analiz nasıl") {
            return technicalAnalysisExplain()
        }
        if q.contains("temel analiz") {
            return fundamentalAnalysisExplain()
        }
        if q.contains("bist nedir") || q.contains("borsa istanbul nedir") {
            return bistExplain()
        }
        if q.contains("endeks nedir") || q.contains("xu100") || q.contains("bist 100 nedir") {
            return indexExplain()
        }
        if q.contains("piyasa özeti") || q.contains("bugün piyasa") || q.contains("genel durum") ||
           q.contains("bist bugün") || q.contains("piyasada neler") {
            return marketSummary(context: context)
        }

        // --- Teknik göstergeler (ek) ---
        if q.contains("golden cross") || q.contains("altin kesisim") || q.contains("altın kesişim") {
            return goldenCrossExplain()
        }
        if q.contains("death cross") || q.contains("olum kesisim") || q.contains("ölüm kesişimi") {
            return deathCrossExplain()
        }
        if q.contains("mum formasyonu") || q.contains("japon mumu") || q.contains("candlestick") ||
           q.contains("mum grafik") || q.contains("mum pattern") {
            return candlestickExplain()
        }
        if q.contains("pivot") {
            if let sym = context.symbol, context.hasData {
                return pivotAnalysis(sym: sym, context: context)
            }
            return pivotExplain()
        }
        if q.contains("kırılım") || q.contains("kirilim") || q.contains("breakout") {
            return breakoutExplain()
        }
        if q.contains("likidite") && (q.contains("nedir") || q.contains("ne demek") || q.contains("önemi") || q.contains("neden")) {
            return liquidityExplain()
        }
        if q.contains("ema") && q.contains("sma") {
            return emaVsSmaExplain()
        }

        // --- Temel analiz (ek) ---
        if q.contains("roe") || q.contains("roa") ||
           (q.contains("özkaynak karlılığı") || q.contains("ozkaynak karliligi")) {
            return roeRoaExplain()
        }
        if q.contains("ev/ebitda") || q.contains("ebitda") {
            return evEbitdaExplain()
        }
        if q.contains("net kar marjı") || q.contains("net kar marji") || q.contains("kar marjı") {
            return netMarginExplain()
        }
        if q.contains("borç/özsermaye") || q.contains("borcozs") || q.contains("borç özsermaye") ||
           q.contains("finansal kaldıraç") || q.contains("kaldiraç") {
            return debtEquityExplain()
        }
        if q.contains("cari oran") {
            return currentRatioExplain()
        }
        if q.contains("gelir büyüme") || q.contains("gelir buyume") || q.contains("yoy") ||
           q.contains("yıllık büyüme") || q.contains("büyüme analiz") {
            return revenueGrowthExplain()
        }
        if q.contains("sektör analiz") || q.contains("sektor analiz") {
            return sectorAnalysisExplain()
        }
        if q.contains("bilanço") || q.contains("bilanco") {
            return balanceSheetExplain()
        }
        if q.contains("gelir tablosu") {
            return incomeStatementExplain()
        }
        if q.contains("nakit akış") || q.contains("nakit akis") || q.contains("cash flow") {
            return cashFlowExplain()
        }

        // --- Strateji & Eğitim ---
        if q.contains("stop-loss") || q.contains("stop loss") || q.contains("zarar durdur") {
            return stopLossExplain()
        }
        if q.contains("trailing stop") || q.contains("izleyen stop") {
            return trailingStopExplain()
        }
        if q.contains("risk") && (q.contains("getiri") || q.contains("oran") || q.contains("nedir")) {
            return riskReturnExplain()
        }
        if q.contains("uzun pozisyon") || q.contains("long pozisyon") || q.contains("long nedir") ||
           (q.contains("long") && q.contains("nedir")) {
            return longPositionExplain()
        }
        if q.contains("açığa satış") || q.contains("aciga satis") || q.contains("short selling") ||
           (q.contains("short") && q.contains("nedir")) {
            return shortSellingExplain()
        }
        if q.contains("dca") || q.contains("dollar-cost") || q.contains("periyodik yatırım") ||
           q.contains("düzenli yatırım") || q.contains("averaging") {
            return dcaExplain()
        }
        if q.contains("swing trading") || q.contains("swing trade") {
            return swingTradingExplain()
        }
        if q.contains("momentum trading") || q.contains("momentum trade") ||
           (q.contains("momentum") && q.contains("strateji")) {
            return momentumTradingExplain()
        }
        if q.contains("pozisyon boyutu") || q.contains("pozisyon büyüklüğü") || q.contains("konum büyüklüğü") {
            return positionSizingExplain()
        }
        if q.contains("teknik mi temel mi") || q.contains("teknik mi yoksa temel") {
            return techVsFundamentalExplain()
        }
        if q.contains("piyasa riski") {
            return marketRiskExplain()
        }

        // --- Piyasa & Kavramlar ---
        if q.contains("hisse senedi nedir") || q.contains("hisse nedir") {
            return stockExplain()
        }
        if q.contains("lot nedir") || (q.contains("lot") && q.contains("ne demek")) {
            return lotExplain()
        }
        if q.contains("halka arz") || q.contains("ipo nedir") {
            return ipoExplain()
        }
        if q.contains("döviz") && (q.contains("etki") || q.contains("hisse")) {
            return currencyEffectExplain()
        }
        if q.contains("enflasyon") && (q.contains("etki") || q.contains("hisse") || q.contains("borsa")) {
            return inflationEffectExplain()
        }
        if q.contains("faiz") && (q.contains("etki") || q.contains("hisse") || q.contains("borsa")) {
            return interestRateEffectExplain()
        }
        if q.contains("küresel") || q.contains("kuresel") || q.contains("abd borsa") ||
           q.contains("amerikan borsa") || q.contains("sp500") || q.contains("dow jones") {
            return globalMarketsExplain()
        }
        if q.contains("piyasa saati") || q.contains("işlem saati") || q.contains("borsa saat") {
            return marketHoursExplain()
        }
        if q.contains("devre kesici") || q.contains("circuit breaker") {
            return circuitBreakerExplain()
        }
        if q.contains("haber") && (q.contains("etki") || q.contains("hisse") || q.contains("fiyat")) {
            return newsEffectExplain()
        }
        if q.contains("bist 30") || q.contains("bist 50") || q.contains("xu030") || q.contains("xu050") {
            return bist3050Explain()
        }

        // --- Hisseye özel sorgular ---
        if let sym = context.symbol, context.hasData {
            let symLow = sym.lowercased()

            // Pivot noktaları
            if q.contains("pivot") || q.contains("pivot noktası") {
                return pivotAnalysis(sym: sym, context: context)
            }

            // Genel teknik analiz
            let isStockQuery = q.contains(symLow) ||
                               q.contains("bu hisse") || q.contains("bu şirket") ||
                               q.contains("analiz") || q.contains("ne düşün") || q.contains("nasıl") ||
                               q.contains("teknik") || q.contains("gösterg") || q.contains("durum") ||
                               q.contains("yorumla") || q.contains("değerlendir") ||
                               q.contains("fiyat") || q.contains("rsi") || q.contains("macd") ||
                               q.contains("hacim") || q.contains("volatil") || q.contains("trend") ||
                               q.contains("momentum") || q.contains("performans")

            if isStockQuery {
                return stockAnalysis(sym: sym, context: context)
            }
        }

        // --- Genel soru: bağlamda hisse var ---
        if let sym = context.symbol, context.hasData {
            if q.contains("fiyat") || q.contains("değişim") || q.contains("kaç tl") || q.contains("ne kadar") {
                return priceInfo(sym: sym, context: context)
            }
        }

        return nil
    }

    // MARK: - Comprehensive rule-based response
    private func ruleBasedResponse(query: String, context: AssistantContext) -> String {
        let q = query.lowercased()

        // Hisseye özel context varsa her zaman analiz yap
        if let sym = context.symbol, context.hasData {
            return stockAnalysis(sym: sym, context: context)
        }

        if q.contains("al") || q.contains("sat") || q.contains("tavsiy") ||
           q.contains("kesin") || q.contains("garantil") {
            return investmentAdviceRefusal()
        }

        if q.contains("hangi hisse") || q.contains("ne alayım") || q.contains("öneri") {
            return stockPickRefusal()
        }

        if q.contains("portföy") || q.contains("çeşitlendir") {
            return portfolioDiversificationInfo()
        }

        if q.contains("merhaba") || q.contains("selam") || q.contains("nasılsın") || q == "hi" || q == "hey" {
            return greetingResponse()
        }

        if q.contains("teşekkür") || q.contains("sağ ol") || q.contains("thanks") {
            return """
            Rica ederim! Başka soruların olursa sormaktan çekinme.

            Hisse analizi için sembolü yaz (örn: **THYAO analiz**), kavram için "RSI nedir", "MACD nedir" gibi sorularını iletebilirsin.

            **Bu bir yatırım tavsiyesi değildir.**
            """
        }

        // Son çare: daha spesifik ol
        return defaultResponse()
    }

    // MARK: - Stock Analysis
    private func stockAnalysis(sym: String, context: AssistantContext) -> String {
        var lines: [String] = ["## \(sym) — Teknik Analiz\n"]

        // Fiyat bilgisi
        if let q = context.quote {
            let sign = q.changePercent >= 0 ? "+" : ""
            let trend = q.changePercent >= 2 ? "güçlü yükseliş" :
                        q.changePercent >= 0 ? "hafif yükseliş" :
                        q.changePercent >= -2 ? "hafif düşüş" : "güçlü düşüş"
            lines.append("**Fiyat:** \(q.formattedPrice)  (\(sign)\(String(format: "%.2f", q.changePercent))% — \(trend))")
            lines.append("**Açılış:** \(String(format: "%.2f ₺", q.open))  **Yüksek:** \(String(format: "%.2f ₺", q.high))  **Düşük:** \(String(format: "%.2f ₺", q.low))")
            lines.append("**Hacim:** \(q.formattedVolume)\n")
        } else {
            lines.append("_Fiyat verisi alınamadı. Hissenin detay sayfasını ziyaret edin._\n")
        }

        // Teknik göstergeler
        if let snap = context.snapshot {
            lines.append("**Teknik Göstergeler:**")

            if let rsi = snap.rsi14 {
                let label = rsiInterpret(rsi)
                let emoji = rsi < 30 ? "🔵" : rsi > 70 ? "🔴" : "🟡"
                lines.append("\(emoji) RSI(14): **\(String(format: "%.1f", rsi))** → \(label)")
            }
            if let sma20 = snap.sma20, let q = context.quote {
                let diff = ((q.lastPrice - sma20) / sma20) * 100
                let pos = q.lastPrice > sma20 ? "üzerinde ▲" : "altında ▼"
                lines.append("📈 MA20: \(String(format: "%.2f ₺", sma20)) — fiyat \(pos) (\(String(format: "%+.1f%%", diff)))")
            }
            if let sma50 = snap.sma50, let q = context.quote {
                let diff = ((q.lastPrice - sma50) / sma50) * 100
                let pos = q.lastPrice > sma50 ? "üzerinde ▲" : "altında ▼"
                lines.append("📉 MA50: \(String(format: "%.2f ₺", sma50)) — fiyat \(pos) (\(String(format: "%+.1f%%", diff)))")
            }
            if let vol = snap.volatilityScore {
                let label = volInterpret(vol)
                let emoji = vol < 25 ? "😴" : vol < 50 ? "📊" : vol < 75 ? "⚡" : "🔥"
                lines.append("\(emoji) Volatilite: \(String(format: "%.0f", vol))/100 — \(label)")
            }
            if let vanom = snap.volumeAnomalyPct {
                let emoji = vanom > 200 ? "🚨" : vanom > 150 ? "⚠️" : "ℹ️"
                let label = vanom > 200 ? "Çok yüksek — piyasada önemli gelişme olabilir" :
                            vanom > 150 ? "Anormal artış — dikkat çekici" :
                            vanom > 100 ? "Ortalamanın üzerinde" : "Normal seviye"
                lines.append("\(emoji) Hacim: %\(String(format: "%.0f", vanom)) (20g ort.) — \(label)")
            }

            var periodLines: [String] = []
            if let c7 = snap.change7d {
                let sign = c7 >= 0 ? "+" : ""
                periodLines.append("7g: **\(sign)\(String(format: "%.1f%%", c7))**")
            }
            if let c30 = snap.change30d {
                let sign = c30 >= 0 ? "+" : ""
                periodLines.append("30g: **\(sign)\(String(format: "%.1f%%", c30))**")
            }
            if !periodLines.isEmpty {
                lines.append("📅 Dönem getirisi — " + periodLines.joined(separator: "  "))
            }

            if snap.isUnusualMove, let sigma = snap.unusualMoveSigma {
                lines.append("\n🚨 **Olağandışı Hareket:** \(String(format: "%.1f", sigma))σ — bugünkü hareket normal dalgalanmanın çok üzerinde.")
            }
        } else if context.candles.count < 15 {
            lines.append("_Teknik göstergeler için yeterli geçmiş veri yok (min. 15 gün gerekir)._")
        }

        // Finansallar
        if let f = context.fundamentals {
            var fundaLines: [String] = []
            if let pe = f.peRatio  { fundaLines.append("F/K: **\(String(format: "%.1f", pe))**") }
            if let pb = f.pbRatio  { fundaLines.append("PD/DD: **\(String(format: "%.2f", pb))**") }
            if let div = f.dividendYield, div > 0 { fundaLines.append("Temettü: **%\(String(format: "%.1f", div))**") }
            if let roe = f.roe     { fundaLines.append("ROE: **%\(String(format: "%.1f", roe))**") }
            if !fundaLines.isEmpty {
                lines.append("\n**Finansal Göstergeler:** " + fundaLines.joined(separator: "  •  "))
            }
        }

        // İçgörüler
        if !context.insights.isEmpty {
            lines.append("\n**Öne Çıkan Sinyaller:**")
            for insight in context.insights.prefix(4) {
                lines.append("• \(insight.title) — \(insight.body.prefix(80))…")
            }
        }

        lines.append("\n**Bu bir yatırım tavsiyesi değildir.**")
        return lines.joined(separator: "\n")
    }

    private func priceInfo(sym: String, context: AssistantContext) -> String {
        guard let q = context.quote else {
            return "\(sym) için fiyat verisi yüklenemedi. Hissenin detay sayfasını ziyaret edip tekrar deneyin.\n\n**Bu bir yatırım tavsiyesi değildir.**"
        }
        let sign = q.changePercent >= 0 ? "+" : ""
        return """
        **\(sym) Fiyat Bilgisi**

        • **Güncel:** \(q.formattedPrice) (\(sign)\(String(format: "%.2f", q.changePercent))%)
        • **Açılış / Yüksek / Düşük:** \(String(format: "%.2f ₺", q.open)) / \(String(format: "%.2f ₺", q.high)) / \(String(format: "%.2f ₺", q.low))
        • **Hacim:** \(q.formattedVolume)

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    // MARK: - Support / Resistance Analysis
    private func supportResistanceAnalysis(sym: String, context: AssistantContext) -> String {
        let candles = context.candles
        guard candles.count >= 20 else {
            return """
            **\(sym) — Destek/Direnç**

            Yeterli geçmiş veri yok (min. 20 mum gerekir).

            **Bu bir yatırım tavsiyesi değildir.**
            """
        }

        let current = context.quote?.lastPrice ?? candles.last?.close ?? 0
        let sr = SupportResistanceCalculator.compute(candles: candles)

        var lines: [String] = ["## \(sym) — Destek & Direnç Seviyeleri\n"]
        lines.append("**Güncel Fiyat:** \(String(format: "%.2f ₺", current))\n")

        // Pivot Points (önceki mum bazlı)
        if let pivs = SupportResistanceCalculator.pivots(candles: candles) {
            lines.append("**Pivot Noktaları** _(önceki seans H/L/C bazlı)_")
            lines.append("• **Pivot (PP):** \(String(format: "%.2f ₺", pivs.pp))")
            lines.append("• **Direnç 1 (R1):** \(String(format: "%.2f ₺", pivs.r1))")
            lines.append("• **Direnç 2 (R2):** \(String(format: "%.2f ₺", pivs.r2))")
            lines.append("• **Destek 1 (S1):** \(String(format: "%.2f ₺", pivs.s1))")
            lines.append("• **Destek 2 (S2):** \(String(format: "%.2f ₺", pivs.s2))")
        }

        // Swing-based levels
        if let sr {
            if !sr.resistances.isEmpty {
                lines.append("\n**Grafik Dirençleri** _(swing high'lardan türetildi)_")
                for (i, r) in sr.resistances.enumerated() {
                    let dist = current > 0 ? ((r - current) / current * 100) : 0
                    lines.append("• R\(i + 1): \(String(format: "%.2f ₺", r))  (\(String(format: "+%.1f%%", dist)) uzaklık)")
                }
            }
            if !sr.supports.isEmpty {
                lines.append("\n**Grafik Destekleri** _(swing low'lardan türetildi)_")
                for (i, s) in sr.supports.reversed().enumerated() {
                    let dist = current > 0 ? ((current - s) / current * 100) : 0
                    lines.append("• S\(i + 1): \(String(format: "%.2f ₺", s))  (\(String(format: "-%.1f%%", dist)) uzaklık)")
                }
            }
        }

        lines.append("""
        \n_Not: Destek ve direnç seviyeleri geçmiş fiyat verilerinden istatistiksel olarak türetilmektedir. Bu seviyeler kesin değildir; piyasa koşulları, haberler ve likidite bu seviyeleri anlık olarak etkiler._

        **Bu bir yatırım tavsiyesi değildir.**
        """)

        return lines.joined(separator: "\n")
    }

    private func pivotAnalysis(sym: String, context: AssistantContext) -> String {
        let candles = context.candles
        guard let pivs = SupportResistanceCalculator.pivots(candles: candles) else {
            return """
            **\(sym) — Pivot Noktaları**

            Pivot hesabı için yeterli veri yok.

            **Bu bir yatırım tavsiyesi değildir.**
            """
        }

        let current = context.quote?.lastPrice ?? candles.last?.close ?? 0
        let pos: String
        if current > pivs.r1        { pos = "R1 direncinin üzerinde — güçlü bölge" }
        else if current > pivs.pp   { pos = "Pivot ile R1 arasında — nötr/güçlü" }
        else if current > pivs.s1   { pos = "Pivot ile S1 arasında — nötr/zayıf" }
        else                         { pos = "S1 desteğinin altında — zayıf bölge" }

        return """
        ## \(sym) — Pivot Noktaları

        **Güncel Fiyat:** \(String(format: "%.2f ₺", current))  →  \(pos)

        | Seviye | Fiyat |
        |--------|-------|
        | R2     | \(String(format: "%.2f ₺", pivs.r2)) |
        | R1     | \(String(format: "%.2f ₺", pivs.r1)) |
        | **PP** | **\(String(format: "%.2f ₺", pivs.pp))** |
        | S1     | \(String(format: "%.2f ₺", pivs.s1)) |
        | S2     | \(String(format: "%.2f ₺", pivs.s2)) |

        _Pivot Noktası (PP) = (Yüksek + Düşük + Kapanış) ÷ 3 formülüyle hesaplanır._

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func marketSummary(context: AssistantContext) -> String {
        return """
        **BIST Genel Piyasa Bilgisi**

        Anlık endeks verilerine (BIST 30, BIST 50, BIST 100) ve piyasa özetine ulaşmak için uygulamanın **Piyasa** sekmesini kullan — orada güncel endeks değerleri, değişimler ve sektör performansları canlı görünür.

        **Bu asistan yalnızca belirli hisseler için analiz yapabilir.**

        Analiz istediğin hissenin sembolünü yaz:
        • `THYAO analiz` → Türk Hava Yolları teknik analizi
        • `GARAN destek direnç` → Garanti Bankası seviyeleri
        • `AKBNK RSI` → Akbank momentum durumu
        • `EREGL temel analiz` → Ereğli Demir Çelik finansalları

        Popüler semboller: **THYAO · GARAN · AKBNK · EREGL · SISE · KCHOL · SAHOL · TUPRS · ASELS · BIMAS**

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    // MARK: - Refusals & soft responses
    private func investmentAdviceRefusal() -> String {
        """
        **Yatırım Tavsiyesi Veremem**

        BIST Radar AI olarak "al", "sat" veya "kesin kazan" gibi yatırım tavsiyeleri vermek etik ve yasal açıdan uygun değildir.

        **Bunun yerine yapabileceklerim:**
        • Teknik göstergeleri (RSI, MACD, hareketli ortalama) açıklamak
        • Belirli bir hissenin verilerini özetlemek
        • Finansal kavramları eğitsel amaçla aktarmak

        Hisse analizi için sembolü yaz (örn: **THYAO analiz**).

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func stockPickRefusal() -> String {
        """
        **Hisse Önerisi Yapamam**

        Bireysel hisse önerisinde bulunmak yatırım danışmanlığı kapsamındadır.

        **Yapabileceklerim:**
        • Belirli bir hissenin teknik göstergelerini analiz etmek
        • Yükselen/düşen sektörlere bakmak (Piyasa sekmesi)
        • Finansal kavramları açıklamak

        Başlamak için bir sembol yaz: **GARAN**, **THYAO**, **EREGL**...

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func portfolioDiversificationInfo() -> String {
        """
        **Portföy Çeşitlendirmesi**

        Portföy çeşitlendirmesi, yatırımları farklı sektörlere, varlık sınıflarına ve coğrafyalara dağıtarak riski azaltma stratejisidir.

        **Temel ilkeler:**
        • **Sektör dağılımı**: Bankacılık, enerji, teknoloji gibi sektörler farklı dönemlerde farklı performans gösterir.
        • **Korelasyon**: Birlikte yükselen/düşen varlıklar çeşitlilik sağlamaz. Düşük korelasyonlu varlıklar tercih edilir.
        • **Pozisyon büyüklüğü**: Tek bir hisseye yüksek ağırlık vermek riski artırır.
        • **Likit varlıklar**: Gerektiğinde kolayca alınıp satılabilen varlıklar önemlidir.

        Gerçek portföy yönetimi için **lisanslı yatırım danışmanına** başvurmanı öneririm.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func greetingResponse() -> String {
        """
        Merhaba! Ben **BIST Radar AI Asistanı**.

        Şu konularda yardımcı olabilirim:

        • **Hisse analizi**: Sembol yaz → "THYAO analiz", "GARAN nasıl"
        • **Teknik göstergeler**: "RSI nedir", "MACD nedir", "Bollinger bantları"
        • **Temel kavramlar**: "F/K oranı", "Temettü", "Volatilite", "Destek/Direnç"
        • **Piyasa özeti**: "Bugün piyasa durumu"

        Yanıtlarım yalnızca eğitsel ve bilgilendirici niteliktedir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func defaultResponse() -> String {
        """
        Sorunuzu tam anlayamadım. Aşağıdaki formatlarda sormayı deneyin:

        **Hisse analizi:**
        → "THYAO analiz et", "GARAN teknik durum", "AKBNK nasıl gidiyor"

        **Göstergeler:**
        → "RSI nedir", "MACD nedir", "Bollinger bantları", "Stokastik"

        **Temel kavramlar:**
        → "F/K oranı", "PD/DD", "Temettü", "Beta katsayısı", "Volatilite"

        **Piyasa:**
        → "Bugün piyasa özeti", "BIST 100 nedir"

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    // MARK: - Educational content

    private func rsiExplain() -> String {
        """
        **RSI — Göreceli Güç Endeksi**

        RSI, bir varlığın son dönemdeki kazanç ve kayıplarının oranını ölçen **0–100** arası bir momentum göstergesidir. Varsayılan periyot 14 gündür.

        **Bölgeler:**
        • **0–30 → Aşırı satım**: Fiyat görece düşük seyrediyor, güç kaybı olabilir
        • **30–50 → Nötr (zayıf taraf)**: Baskı henüz azalmadı
        • **50–70 → Nötr (güçlü taraf)**: Yükseliş ivmesi devam edebilir
        • **70–100 → Aşırı alım**: Fiyat görece yüksek, ivme yavaşlıyor olabilir

        **Uyarılar:**
        • Güçlü trendlerde RSI uzun süre aşırı alım/satım bölgesinde kalabilir.
        • "Uyumsuzluk" (divergence): Fiyat yeni zirve yaparken RSI yapmıyorsa trend zayıflıyor olabilir.
        • Her zaman diğer göstergelerle (MACD, hacim) birlikte değerlendirilmelidir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func macdExplain() -> String {
        """
        **MACD — Moving Average Convergence Divergence**

        MACD, iki üstel hareketli ortalama (EMA) arasındaki farkı gösteren bir trend/momentum göstergesidir.

        **Hesaplama:**
        • **MACD Çizgisi** = 12 günlük EMA − 26 günlük EMA
        • **Sinyal Çizgisi** = MACD'nin 9 günlük EMA'sı
        • **Histogram** = MACD − Sinyal (çubuklarla gösterilir)

        **Yorumlama:**
        • MACD sinyal çizgisini **yukarı keserse** → pozitif momentum sinyali
        • MACD sinyal çizgisini **aşağı keserse** → negatif momentum sinyali
        • Histogram sıfırı yukarı geçerse → alıcılar güçleniyor
        • Uyumsuzluk (divergence): Fiyat yeni zirve yaparken MACD yapmıyorsa → trend zayıflıyor olabilir

        **Not:** MACD gecikmeli (lagging) bir göstergedir; sürpriz hareketlerde geç sinyal verebilir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func bollingerExplain() -> String {
        """
        **Bollinger Bantları**

        Bollinger Bantları, fiyatın volatilite bazlı üst ve alt sınırlarını gösteren bir göstergedir.

        **Bileşenler:**
        • **Orta bant**: 20 günlük hareketli ortalama (MA20)
        • **Üst bant**: MA20 + 2 standart sapma
        • **Alt bant**: MA20 − 2 standart sapma

        **İstatistiksel anlam:** Fiyatın ~%95'i bantların içinde kalır.

        **Yorumlama:**
        • **Bant daralması (sıkışma)**: Volatilite düşmüş, büyük bir hareket yaklaşıyor olabilir
        • **Bant genişlemesi**: Volatilite artmış, trend güçlenmiş olabilir
        • **Fiyat üst banda değerse**: Görece pahalı bölge
        • **Fiyat alt banda değerse**: Görece ucuz bölge
        • **Bant dışına çıkış**: Olağandışı hareket; trend devam edebilir ya da geri dönüş gelebilir

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func stochasticExplain() -> String {
        """
        **Stokastik Osilatör**

        Stokastik, fiyatın belirli bir periyodun fiyat aralığı içindeki konumunu gösteren bir momentum göstergesidir.

        **Hesaplama (Slow Stochastic %K ve %D):**
        • **%K** = (Son Kapanış − Periyodun En Düşüğü) ÷ (Periyodun En Yükseği − En Düşüğü) × 100
        • **%D** = %K'nın 3 günlük hareketli ortalaması (sinyal çizgisi)

        **Bölgeler:**
        • **80 üstü → Aşırı alım**: Fiyat, periyodun en yükseklerine yakın
        • **20 altı → Aşırı satım**: Fiyat, periyodun en düşüklerine yakın

        **Sinyaller:**
        • %K, %D'yi yukarı keserse → güçlenme sinyali
        • %K, %D'yi aşağı keserse → zayıflama sinyali
        • RSI ile birlikte kullanılması güvenilirliği artırır

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func atrExplain() -> String {
        """
        **ATR — Average True Range (Ortalama Gerçek Aralık)**

        ATR, bir varlığın belirli bir periyottaki ortalama günlük fiyat aralığını ölçer. Volatilitenin yönden bağımsız bir ölçüsüdür.

        **Hesaplama (True Range — TR):**
        TR = max(Yüksek − Düşük, |Yüksek − Önceki Kapanış|, |Düşük − Önceki Kapanış|)
        ATR = TR'nin 14 günlük ortalaması

        **Kullanım alanları:**
        • **Stop-loss belirleme**: ATR x 1.5 gibi çarpanlarla dinamik stop seviyeleri
        • **Pozisyon boyutlandırma**: Yüksek ATR = daha küçük pozisyon (aynı risk için)
        • **Volatilite karşılaştırma**: Sektörler veya dönemler arası karşılaştırma

        **Not:** ATR yön bilgisi vermez; sadece oynaklık büyüklüğünü gösterir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func obvExplain() -> String {
        """
        **OBV — On Balance Volume (Dengeli Hacim)**

        OBV, hacim akışının fiyat değişimini ne ölçüde desteklediğini gösteren bir göstergedir.

        **Hesaplama:**
        • Fiyat yükselirse: OBV = OBV (önceki) + Günün hacmi
        • Fiyat düşerse: OBV = OBV (önceki) − Günün hacmi

        **Yorumlama:**
        • OBV **yükseliyorsa**: Alıcılar hâkim, hacim fiyat artışını destekliyor
        • OBV **düşüyorsa**: Satıcılar hâkim, hacim fiyat düşüşünü destekliyor
        • **Uyumsuzluk**: Fiyat yeni zirve yaparken OBV yapmıyorsa → trend zayıf olabilir

        OBV özellikle hacim anomalilerini erken tespit etmekte kullanılır.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func maExplain() -> String {
        """
        **Hareketli Ortalama (MA / SMA / EMA)**

        Hareketli ortalama, belirli bir dönemin kapanış fiyatlarının ortalamasıdır. Trendin yönünü düzleştirilmiş biçimde gösterir.

        **Türleri:**
        • **SMA (Basit)**: Tüm günler eşit ağırlıklı
        • **EMA (Üstel)**: Son günlere daha fazla ağırlık verir, daha hızlı tepki verir

        **Periyotlar:**
        • **MA20**: Kısa vadeli trend. Hızlı değişir, gürültülüdür.
        • **MA50**: Orta vadeli trend. Daha kararlı.
        • **MA200**: Uzun vadeli trend. Yıllık tablo.

        **Kesişim sinyalleri:**
        • **Altın Kesişim**: MA20, MA50'yi yukarı kesiyor → yükseliş eğilimi güçleniyor
        • **Ölüm Kesişimi**: MA20, MA50'yi aşağı kesiyor → düşüş eğilimi güçleniyor

        **Not:** Hareketli ortalama geçmişe bakar; gelecekteki hareketi garantilemez.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func volumeExplain() -> String {
        """
        **Hacim (Volume) Nedir?**

        Hacim, belirli bir zaman diliminde alınıp satılan hisse adedi veya toplam işlem değeridir (TL).

        **Neden önemli?**
        • Yüksek hacim eşliğindeki fiyat hareketleri daha **güçlü** kabul edilir.
        • Fiyat yükselirken hacim de yükseliyorsa → yükseliş trendi destekleniyor
        • Fiyat artarken hacim düşüyorsa → trendin zayıflayabileceğine işaret edebilir
        • Düşük hacimli günlerde fiyat hareketleri yanıltıcı olabilir

        **Anormal hacim:**
        BIST Radar, 20 günlük ortalama hacmin **%150 üzerindeki** işlem günlerini anormal olarak işaretler.
        Bu durum; önemli haberler, kurumsal hareketler veya manipülatif işlemler ile ilişkili olabilir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func volatilityExplain() -> String {
        """
        **Volatilite (Oynaklık)**

        Volatilite, fiyatın belirli bir süre içinde ne kadar dalgalandığını ölçer. Genellikle günlük getirilerin standart sapması kullanılarak hesaplanır.

        **BIST Radar Skoru (0–100):**
        • **0–25**: Düşük volatilite — fiyat görece sakin
        • **25–50**: Orta volatilite — normal dalgalanma
        • **50–75**: Yüksek volatilite — belirgin hareketler
        • **75–100**: Çok yüksek — sert ve sık fiyat dalgalanmaları

        **Dikkat:**
        • Volatilite hem yukarı hem aşağı hareketleri kapsar.
        • Yüksek volatilite = yüksek potansiyel kazanç **ve** kayıp.
        • Düşük volatilite birdenbire sona erebilir (sıkışma → patlama).

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func betaExplain() -> String {
        """
        **Beta Katsayısı**

        Beta, bir hissenin piyasa (genellikle BIST 100) ile karşılaştırmalı oynaklığını ölçer.

        **Yorumlama:**
        • **Beta = 1.0**: Piyasa ile aynı hareket
        • **Beta > 1.0** (örn. 1.5): Piyasa %1 yükselince hisse %1.5 yükselir — daha oynak
        • **Beta < 1.0** (örn. 0.6): Piyasa %1 yükselince hisse %0.6 yükselir — daha sakin
        • **Beta < 0**: Piyasayla ters yönde hareket (nadir)

        **Kullanım:**
        • Yüksek beta hisseler yükseliş trendinde daha hızlı kazandırır, düşüşte daha hızlı kaybettirir.
        • Portföy riski ölçümünde önemli bir araçtır.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func supportResistanceExplain() -> String {
        """
        **Destek ve Direnç Seviyeleri**

        Destek ve direnç, teknik analizin temel kavramlarıdır.

        **Destek (Support):**
        Fiyatın daha önce duraksadığı veya yükselişe geçtiği fiyat bölgesidir. Alıcıların devreye girdiği seviye olarak yorumlanır. Fiyat bu bölgeye yaklaşırken alım baskısı artabilir.

        **Direnç (Resistance):**
        Fiyatın daha önce yükselişini durdurup geri döndüğü bölgedir. Satıcıların devreye girdiği seviye olarak yorumlanır.

        **Önemli noktalar:**
        • Destek kırılırsa yeni destek arayışı başlar (eski destek dirence dönüşebilir).
        • Direnç kırılırsa yeni yüksek seviyelere kapı açılabilir.
        • Seviyeler ne kadar çok test edilirse o kadar güçlü kabul edilir.
        • Yuvarlak sayılar (100 ₺, 200 ₺) psikolojik destek/direnç oluşturur.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func trendExplain() -> String {
        """
        **Trend Analizi**

        Trend, fiyatın belirli bir yönde hareket etme eğilimini ifade eder.

        **Üç temel trend:**
        • **Yükseliş trendi (Uptrend)**: Ardışık yüksek tepeler ve yüksek dipler — alıcılar baskın
        • **Düşüş trendi (Downtrend)**: Ardışık düşük tepeler ve düşük dipler — satıcılar baskın
        • **Yatay trend (Sideways)**: Fiyat belirli bir bant içinde dalgalanıyor

        **Vade:**
        • **Kısa vade**: Günler–haftalar (MA20 ile takip edilir)
        • **Orta vade**: Haftalar–aylar (MA50)
        • **Uzun vade**: Aylar–yıllar (MA200)

        **Trend çizgisi:**
        Yükseliş trendinde ardışık dipleri birleştiren çizgi; bu çizginin kırılması trend değişimine işaret edebilir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func marketCapExplain() -> String {
        """
        **Piyasa Değeri (Market Cap)**

        Piyasa değeri = Hisse fiyatı × Dolaşımdaki hisse senedi sayısı

        Şirketin borsadaki toplam değerini gösterir.

        **BIST'te kategoriler:**
        • **Büyük ölçekli (Large Cap)**: Piyasa değeri yüksek, genellikle likid şirketler (THYAO, GARAN, AKBNK...)
        • **Orta ölçekli (Mid Cap)**: Orta büyüklükte şirketler
        • **Küçük ölçekli (Small Cap)**: Küçük şirketler — genellikle daha az likit, daha oynak

        **Dikkat:**
        • Yüksek piyasa değeri tek başına iyi bir yatırım olduğunu göstermez.
        • Freefloat oranı (halka açıklık) likiditeyi doğrudan etkiler.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func technicalAnalysisExplain() -> String {
        """
        **Teknik Analiz Nedir?**

        Teknik analiz, geçmiş fiyat ve hacim verilerini kullanarak gelecekteki fiyat hareketlerini tahmin etmeye çalışan bir yöntemdir.

        **Temel araçlar:**
        • **Göstergeler**: RSI, MACD, Stokastik, Bollinger Bantları, hareketli ortalamalar
        • **Grafik formasyonları**: Baş-omuz, çift tepe, bayrak, üçgen...
        • **Destek/Direnç**: Kritik fiyat seviyeleri
        • **Trend çizgileri**: Hareketin yönünü gösterir
        • **Hacim analizi**: Hareketin güçlü olup olmadığını onaylar

        **Temel analiz ile farkı:**
        Temel analiz şirketin gerçek değerini (kâr, büyüme, bilanço) inceler.
        Teknik analiz yalnızca piyasa davranışına (fiyat, hacim) odaklanır.

        **Sınırlılıklar:**
        Teknik analiz olasılıklar sunar; kesin sonuç vermez. Sürpriz haberler, makroekonomik gelişmeler analizi geçersiz kılabilir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func fundamentalAnalysisExplain() -> String {
        """
        **Temel Analiz Nedir?**

        Temel analiz, bir şirketin gerçek (içsel) değerini belirlemek için finansal ve ekonomik verileri inceler.

        **İncelenen göstergeler:**
        • **Gelir tablosu**: Ciro, kâr marjları, büyüme
        • **Bilanço**: Varlıklar, borçlar, özkaynaklar
        • **Nakit akışı**: Operasyonel nakit üretimi
        • **Oranlar**: F/K, PD/DD, EV/EBITDA, temettü verimi, ROE, ROA

        **BIST Radar'da:**
        Her hissenin detay sayfasında F/K, PD/DD, temettü verimi ve büyüme verilerini görebilirsin.

        **Teknik analize göre farkı:**
        Temel analiz şirketin "değer"ini sorgular; teknik analiz piyasanın "ne yapacağını" tahmin etmeye çalışır.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func peExplain() -> String {
        """
        **F/K Oranı (Fiyat/Kazanç — P/E)**

        F/K = Hisse Fiyatı ÷ Hisse Başına Net Kâr

        Örnek: F/K = 12 → Yatırımcı, 1 TL kazanç için 12 TL ödüyor.

        **Yorumlama:**
        • **Düşük F/K**: Kazanca göre ucuz görünüyor olabilir — ancak düşük büyüme beklentisi ya da sorunlu bilanço da yansıtıyor olabilir.
        • **Yüksek F/K**: Fiyat pahalı görünebilir — ancak yüksek büyüme beklentisi de içeriyor olabilir.
        • **Negatif F/K**: Şirket zarar ediyor.

        **Kritik not:**
        F/K tek başına yeterli değildir. Sektör ortalaması, şirketin büyüme hızı (PEG oranı) ve diğer göstergelerle birlikte değerlendirilmelidir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func pbExplain() -> String {
        """
        **PD/DD Oranı (Piyasa Değeri / Defter Değeri — P/B)**

        PD/DD = Piyasa Değeri ÷ Özkaynak (Defter Değeri)

        • **PD/DD < 1**: Şirket, defter değerinin altında fiyatlanıyor — potansiyel düşük değerleme ya da zayıf bilanço sinyali
        • **PD/DD = 1**: Piyasa, şirketi defter değeriyle eşit görüyor
        • **PD/DD > 1**: Piyasa, yönetim kalitesi, büyüme beklentisi gibi faktörler için ek ödüyor

        Bankacılık ve finans sektöründe en yaygın kullanılan değerleme ölçütüdür.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func dividendExplain() -> String {
        """
        **Temettü (Dividend)**

        Temettü, şirketin kârından hissedarlarına dağıttığı nakit ödemedir.

        **Temettü Verimi** = (Hisse Başına Temettü ÷ Hisse Fiyatı) × 100

        Örnek: %6 temettü verimi → 100 TL değerindeki hisse için yılda 6 TL temettü.

        **Dikkat edilmesi gerekenler:**
        • Yüksek temettü verimi, düşen hisse fiyatından da kaynaklanıyor olabilir.
        • Şirketin temettü ödeme geçmişi (düzenli mi? kesiyor mu?) önemlidir.
        • BIST'te temettüler genellikle yılda bir kez, Nisan–Haziran arasında dağıtılır.
        • Temettü açıklaması sonrası hisse bedelsiz/rüçhan hakkı da gelebilir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func bistExplain() -> String {
        """
        **BIST — Borsa İstanbul**

        BIST, Türkiye'nin tek menkul kıymetler borsasıdır. 2013 yılında İMKB, VOB ve İAB'nin birleşimiyle kurulmuştur.

        **Temel endeksler:**
        • **BIST 100 (XU100)**: En büyük 100 şirket — ana gösterge endeks
        • **BIST 50 (XU050)**: En büyük 50 şirket
        • **BIST 30 (XU030)**: En likit 30 şirket
        • **Sektör endeksleri**: Bankacılık (XBANK), Sanayi (XUSIN), Teknoloji (XUTEK)...

        **İşlem saatleri:**
        10:00–18:00 (Pazartesi–Cuma, resmi tatiller hariç)
        Sabah seansı öncesi 09:40–09:55 sürekli müzayede.

        **Para birimi:** Türk Lirası (TRY / ₺)

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func indexExplain() -> String {
        """
        **Borsa Endeksi Nedir?**

        Endeks, seçilmiş hisse senetlerinin ağırlıklı ortalama fiyat performansını ölçen istatistiksel bir göstergedir.

        **BIST 100 nasıl hesaplanır?**
        Her hissenin endekse katkısı, piyasa değeriyle orantılıdır. THYAO, GARAN, AKBNK gibi büyük şirketler endeksi daha fazla etkiler.

        **Endeks yükseliyor demek:**
        Bileşen hisselerin ağırlıklı ortalaması yükseliyor demektir; tüm hisseler yükselmek zorunda değildir.

        **Endeks türleri:**
        • **Fiyat endeksi**: Sadece fiyat değişimini ölçer
        • **Getiri endeksi**: Temettüler dahil toplam getiriyi ölçer (BIST genellikle fiyat endeksi kullanır)

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func fibonacciExplain() -> String {
        """
        **Fibonacci Düzeltme Seviyeleri**

        Fibonacci seviyeleri, büyük fiyat hareketlerinden sonra olası destek ve direnç bölgelerini tahmin etmek için kullanılır.

        **Temel seviyeler:** %23.6 · %38.2 · %50.0 · %61.8 · %78.6

        **Nasıl uygulanır:**
        Büyük bir yükseliş hareketinin ardından "geri çekilme" seviyeleri bu oranlara göre hesaplanır.
        Örnek: 100 ₺ → 200 ₺ yükselen bir hisse için %38.2 düzeltmesi ~162 ₺'ye işaret eder.

        **Sınırlamalar:**
        • Fibonacci seviyeleri matematiksel bir teori değil, psikolojik bir konsensüse dayanır.
        • Her zaman çalışmaz; diğer göstergeler ve hacimle teyit edilmelidir.
        • Nereden nereye çizildiği (swing high/low seçimi) sonuçları değiştirir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    // MARK: - Yeni Eğitsel Fonksiyonlar

    private func goldenCrossExplain() -> String {
        """
        **Golden Cross (Altın Kesişim)**

        Golden Cross, kısa vadeli hareketli ortalamanın (genellikle MA20 veya MA50) uzun vadeli hareketli ortalamayı (MA50 veya MA200) **yukarıdan kesmesi** durumudur.

        **En yaygın versiyon:** MA50, MA200'ü yukarı kesiyor.

        **Teknik yorumu:**
        • Kısa vadeli momentum uzun vadeli momentumu geçiyor → yükseliş eğilimi güçleniyor
        • Kurumsal yatırımcıların bazı stratejilerinde otomatik alım sinyali sayılır

        **Sınırlamalar:**
        • Gecikmeli (lagging) bir sinyal — fiyat zaten yükseldikten sonra oluşur
        • Yatay piyasalarda yanlış sinyal üretebilir
        • Hacimle teyit edilmelidir

        BIST Radar, Golden Cross oluşumunu Insight panelinde otomatik işaretler.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func deathCrossExplain() -> String {
        """
        **Death Cross (Ölüm Kesişimi)**

        Death Cross, kısa vadeli hareketli ortalamanın (MA20 veya MA50) uzun vadeli hareketli ortalamayı (MA50 veya MA200) **aşağıdan kesmesi** durumudur.

        **Teknik yorumu:**
        • Kısa vadeli momentum uzun vadeli momentumun altına düşüyor → düşüş eğilimi güçleniyor
        • Koruyucu emir (stop-loss) seviyeleri gözden geçirilmesi gereken bir sinyal olarak yorumlanır

        **Sınırlamalar:**
        • Gecikmeli sinyal — fiyat zaten düştükten sonra oluşur
        • Her Death Cross uzun süreli düşüşe yol açmaz; kısa süre içinde toparlanma olabilir
        • Volum ve diğer göstergeler ile birlikte değerlendirilmeli

        BIST Radar, Death Cross oluşumunu Insight panelinde uyarı olarak işaretler.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func candlestickExplain() -> String {
        """
        **Japon Mum Formasyonları**

        Mum grafikleri, bir seansın açılış, kapanış, yüksek ve düşük fiyatlarını görsel olarak gösterir.

        **Temel mum yapısı:**
        • **Gövde**: Açılış–Kapanış arası (yeşil/beyaz = yükselen, kırmızı/siyah = düşen)
        • **Fitil (gölge)**: Gövdenin dışına uzanan çizgiler (yüksek/düşük seviyeleri)

        **Önemli tek mum formasyonları:**
        • **Doji**: Açılış ≈ Kapanış — kararsızlık
        • **Çekiç (Hammer)**: Uzun alt fitil, küçük gövde — potansiyel dip sinyali
        • **Saplı Yıldız (Shooting Star)**: Uzun üst fitil, küçük gövde — potansiyel tepe sinyali
        • **Marubozu**: Fitilin olmadığı uzun gövde — güçlü yönlü baskı

        **Önemli çift/üçlü mum formasyonları:**
        • **Sabah Yıldızı (Morning Star)**: Düşüş sonrası 3 mum — potansiyel dönüş
        • **Akşam Yıldızı (Evening Star)**: Yükseliş sonrası 3 mum — potansiyel dönüş
        • **Engulfing (Yutan)**: Önceki mumu tamamen yutan mum — güçlü sinyal

        **Not:** Formasyonlar tek başına yeterli değildir; hacim ve trend bağlamı şarttır.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func pivotExplain() -> String {
        """
        **Pivot Noktaları (PP, R1, R2, S1, S2)**

        Pivot noktaları, önceki seansın yüksek (H), düşük (L) ve kapanış (C) fiyatlarından hesaplanan destek/direnç seviyeleridir.

        **Formüller:**
        • **PP** = (H + L + C) ÷ 3
        • **R1** = 2 × PP − L
        • **R2** = PP + (H − L)
        • **S1** = 2 × PP − H
        • **S2** = PP − (H − L)

        **Yorumlama:**
        • Fiyat PP'nin üzerinde → gün genel olarak pozitif
        • Fiyat PP'nin altında → gün genel olarak negatif
        • R1/R2 → olası direnç seviyeleri
        • S1/S2 → olası destek seviyeleri

        BIST Radar, her hissenin detay sayfasında pivot noktalarını gösterir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func breakoutExplain() -> String {
        """
        **Kırılım (Breakout)**

        Kırılım, fiyatın belirlenmiş bir destek veya direnç seviyesini geçmesidir.

        **Türleri:**
        • **Yukarı kırılım**: Direnç seviyesi aşıldı → yükseliş ivmesi artıyor olabilir
        • **Aşağı kırılım**: Destek seviyesi kırıldı → düşüş ivmesi artıyor olabilir

        **Kırılım güvenilirliği nasıl değerlendirilir?**
        • **Hacim**: Yüksek hacimle gerçekleşen kırılım daha anlamlı kabul edilir
        • **Kapanış**: Kırılım seansında fiyatın seviyenin üzerinde/altında kapanması önemli
        • **Yeniden test (retest)**: Kırılan seviyeye geri dönüş (eski direnç artık destek mi?)

        **Sahte kırılım (Fakeout):**
        Fiyat seviyeyi geçer ama hemen geri döner — hacim düşükse risk artar.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func liquidityExplain() -> String {
        """
        **Likidite**

        Likidite, bir varlığın fiyatı önemli ölçüde etkilemeden ne kadar hızlı alınıp satılabileceğini ifade eder.

        **BIST'te likidite göstergeleri:**
        • **Günlük işlem hacmi (TL)**: Yüksek hacim = yüksek likidite
        • **Alış-satış fiyat farkı (spread)**: Dar spread = likit piyasa
        • **BIST 30**: En likit 30 hisseyi içerir

        **Neden önemli?**
        • Düşük likit hisseler → daha geniş spread, istenen fiyattan işlem zorluğu
        • Ani satış durumunda büyük fiyat hareketi yaratabilir
        • Kurumsal yatırımcılar likit hisseleri tercih eder

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func emaVsSmaExplain() -> String {
        """
        **EMA vs SMA — Fark Nedir?**

        Her ikisi de hareketli ortalama türüdür; fark ağırlıklandırma yöntemindedir.

        **SMA (Simple Moving Average — Basit Hareketli Ortalama):**
        • Tüm dönemlere eşit ağırlık verir
        • Hesaplama: Son N günün kapanışlarının ortalaması
        • Daha yavaş tepki verir, gürültüyü daha iyi filtreler

        **EMA (Exponential Moving Average — Üstel Hareketli Ortalama):**
        • Son günlere daha fazla ağırlık verir (üstel azalan ağırlık)
        • Fiyat değişimlerine daha hızlı tepki verir
        • Kısa vadeli sinyal üretiminde SMA'ya göre öne çıkar

        **Hangisi daha iyi?**
        • Hızlı sinyal gerekiyorsa → EMA
        • Trend yönünü uzun vadede görmek istiyorsanız → SMA
        • MACD, varsayılan olarak EMA kullanır (EMA12 − EMA26)

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func roeRoaExplain() -> String {
        """
        **ROE ve ROA**

        **ROE (Return on Equity — Özkaynak Kârlılığı):**
        ROE = Net Kâr ÷ Ortalama Özkaynak × 100

        Şirketin hissedarların yatırımından ne kadar kâr ürettiğini gösterir.
        • ROE > %15 → genellikle güçlü kabul edilir (sektöre göre değişir)
        • Yüksek borçla şişirilebilir — borç/özsermaye ile birlikte yorumlanmalı

        **ROA (Return on Assets — Aktif Kârlılığı):**
        ROA = Net Kâr ÷ Toplam Varlıklar × 100

        Şirketin tüm varlıklarından ne kadar kâr ürettiğini gösterir.
        • Borç düzeyinden daha az etkilenir → ROE'den daha sağlıklı karşılaştırma sağlar
        • ROA > %5 → genellikle iyi kabul edilir

        **ROE vs ROA farkı:**
        ROE yüksek, ROA düşükse → şirket kârını büyük ölçüde borçla üretiyor olabilir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func evEbitdaExplain() -> String {
        """
        **EV/EBITDA**

        **EV (Enterprise Value — Şirket Değeri):**
        EV = Piyasa Değeri + Net Borç (Borç − Nakit)

        **EBITDA:** Faiz, Vergi, Amortisman ve İtfa Öncesi Kâr

        **EV/EBITDA = Şirket Değeri ÷ EBITDA**

        **Neden kullanılır?**
        • F/K'nın aksine borç yapısından bağımsız karşılaştırma sağlar
        • Farklı ülke ve sektördeki şirketleri karşılaştırmak için yaygın kullanılır
        • Özellikle M&A (birleşme-satın alma) analizinde temel metriktir

        **Yorumlama:**
        • Düşük EV/EBITDA → göreceli ucuz görünüm (sektör ortalamasına göre)
        • Yüksek EV/EBITDA → büyüme beklentisi veya prim içeriyor olabilir
        • Sektör bazlı yorumlanmalı (teknoloji vs. enerji çok farklı)

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func netMarginExplain() -> String {
        """
        **Net Kâr Marjı**

        Net Kâr Marjı = (Net Kâr ÷ Net Satışlar) × 100

        Her 100 TL gelirden kaç TL net kâr kaldığını gösterir.

        **Örnek:** %12 net kâr marjı → 100 TL satıştan 12 TL net kâr.

        **Yorumlama:**
        • Yüksek marj → maliyet kontrolü iyi, rekabet avantajı olabilir
        • Düşük marj → rekabetçi sektör ya da yüksek maliyetler
        • Sektörler arası büyük fark: Perakende genellikle %2–5, teknoloji %20+

        **BIST'te dikkat:**
        Enflasyon ortamında stok değer artışı net kârı şişirebilir — operasyonel kâra da bakılmalı.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func debtEquityExplain() -> String {
        """
        **Borç/Özsermaye Oranı (D/E)**

        D/E = Toplam Borç ÷ Toplam Özkaynak

        Şirketin ne kadar borçla finanse edildiğini gösterir.

        **Yorumlama:**
        • **D/E < 1**: Özkaynak ağırlıklı finansman — görece düşük finansal risk
        • **D/E = 1–2**: Orta kaldıraç — sektöre göre değişir
        • **D/E > 2**: Yüksek borç yükü — faiz yükü kârı eritebilir

        **Sektörel farklılıklar:**
        • Bankacılık doğası gereği yüksek D/E ile çalışır — bankalar için farklı metrikler kullanılır
        • Enerji ve altyapı şirketleri yüksek sabit varlık nedeniyle daha fazla borçlanır
        • Teknoloji şirketleri genellikle düşük D/E ile çalışır

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func currentRatioExplain() -> String {
        """
        **Cari Oran (Current Ratio)**

        Cari Oran = Dönen Varlıklar ÷ Kısa Vadeli Borçlar

        Şirketin kısa vadeli borçlarını dönen varlıklarıyla karşılayıp karşılayamayacağını gösterir.

        **Yorumlama:**
        • **< 1**: Kısa vadeli borçlar dönen varlıkları aşıyor — likidite riski
        • **1–2**: Yeterli likidite (çoğu sektörde kabul edilebilir)
        • **> 2**: Güçlü likidite — ancak çok yüksekse varlıkların verimsiz kullanımı olabilir

        **Hızlı oran (Quick Ratio):**
        Cari orandan stok çıkarılır → daha muhafazakâr likidite ölçütü

        Cari oran sektör ve iş modeline göre yorumlanmalıdır.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func revenueGrowthExplain() -> String {
        """
        **Gelir Büyümesi (YoY)**

        YoY (Year-over-Year) büyüme, bir dönemin önceki yılın aynı dönemiyle karşılaştırılmasıdır.

        **Gelir Büyümesi = (Bu Yıl − Geçen Yıl) ÷ Geçen Yıl × 100**

        **Neden önemli?**
        • Şirketin büyüme hikayesini anlamanın temel yoludur
        • Net kâr büyümesi gelir büyümesinden hızlıysa → verimlilik artıyor
        • Yüksek enflasyon ortamında reel büyüme (enflasyon düşülmüş) daha anlamlıdır

        **BIST'te dikkat:**
        TL cinsinden yüksek büyüme enflasyonu yansıtıyor olabilir.
        Döviz gelirleri olan şirketlerde kur etkisi büyümeyi yukarı/aşağı çekebilir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func sectorAnalysisExplain() -> String {
        """
        **Sektör Analizi**

        Sektör analizi, bir sektördeki şirketleri karşılaştırmalı olarak değerlendirme yöntemidir.

        **Adımlar:**
        1. Sektörün makro bağlamı (faiz, enflasyon, döviz hangi sektörü nasıl etkiler?)
        2. Sektör büyüme beklentisi (talep artıyor mu?)
        3. Rekabet yapısı (kaç oyuncu? pazar payı dağılımı?)
        4. Şirketlerin sektör içi karşılaştırması (F/K, PD/DD, ROE ortalamaları)
        5. Öne çıkan ve geride kalan şirketlerin değerlendirmesi

        **BIST'te ana sektörler:**
        Bankacılık · Sanayi · Enerji · Perakende · Teknoloji · İnşaat · Havacılık · Sigorta

        BIST Radar'ın Piyasa sekmesinde sektör bazlı performans karşılaştırması mevcuttur.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func balanceSheetExplain() -> String {
        """
        **Bilanço Nasıl Okunur?**

        Bilanço (Balance Sheet), bir şirketin belirli bir tarihteki varlık, borç ve özkaynak durumunu gösterir.

        **Temel denklem:**
        Varlıklar = Borçlar + Özkaynaklar

        **Varlıklar (Assets):**
        • Dönen varlıklar: Nakit, alacaklar, stoklar (1 yıl içinde nakde çevrilir)
        • Duran varlıklar: Bina, makine, arazi, maddi olmayan varlıklar

        **Borçlar (Liabilities):**
        • Kısa vadeli borçlar: 1 yıl içinde ödenecek
        • Uzun vadeli borçlar: 1 yıldan uzun vadeli

        **Özkaynaklar (Equity):**
        Varlıklar − Borçlar = Özkaynak (şirketin net değeri)

        **İzlenecek sinyaller:**
        • Özkaynak sürekli azalıyorsa → dikkat
        • Borç/varlık oranı yükseliyorsa → kaldıraç artıyor
        • Nakit pozisyonu güçlüyse → finansal esneklik var

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func incomeStatementExplain() -> String {
        """
        **Gelir Tablosu Nasıl Okunur?**

        Gelir tablosu (Income Statement), bir dönemde şirketin ne kadar gelir elde ettiğini ve kâra dönüştürebildiğini gösterir.

        **Temel kalemler (yukarıdan aşağıya):**
        1. **Net Satışlar (Ciro)**: Toplam satış geliri
        2. **Satışların Maliyeti**: Üretim/satın alma maliyetleri
        3. **Brüt Kâr** = Satışlar − Satış Maliyeti
        4. **Faaliyet Giderleri**: Personel, kira, pazarlama vb.
        5. **EBITDA**: Faiz+Vergi+Amortisman öncesi kâr
        6. **Faaliyet Kârı (EBIT)**
        7. **Finansal Gelir/Gider**: Faiz geliri/gideri, kur farkları
        8. **Vergi Öncesi Kâr**
        9. **Net Kâr**: Son satır — hissedara düşen kâr

        **İpucu:** Brüt kâr marjı yüksek ama net kâr düşükse → yönetim giderleri veya finansal maliyetler yüksek.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func cashFlowExplain() -> String {
        """
        **Nakit Akışı (Cash Flow)**

        Nakit akış tablosu, şirketin dönem içindeki nakit giriş ve çıkışlarını gösterir. Kâr yazılabilir ama nakit olmayabilir — bu yüzden önemlidir.

        **Üç ana bölüm:**
        • **Operasyonel nakit akışı**: Asıl işten üretilen nakit (en önemli)
        • **Yatırım nakit akışı**: Varlık alım/satımı (negatif olması yatırım yapıldığını gösterebilir)
        • **Finansman nakit akışı**: Borç alma/geri ödeme, temettü ödemeleri

        **Serbest Nakit Akışı (Free Cash Flow — FCF):**
        FCF = Operasyonel Nakit − Sermaye Harcamaları

        FCF pozitif ve yüksekse → şirket kendi kendini fonlayabiliyor, borç azaltabilir veya temettü ödeyebilir.

        **Dikkat:** Kâr var ama FCF negatifse → dikkat (alacaklar veya stoklar şişmiş olabilir).

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func stopLossExplain() -> String {
        """
        **Stop-Loss (Zarar Durdurma)**

        Stop-loss, bir pozisyon belirli bir fiyat seviyesine düştüğünde otomatik olarak kapatılmasını sağlayan emirdir.

        **Amaç:** Önceden kabul edilen maksimum kaybı sınırlamak.

        **Belirleme yöntemleri:**
        • **Sabit yüzde**: Giriş fiyatının %5–10 altı (örn. 100 ₺'den girdim, 90 ₺'de stop)
        • **ATR bazlı**: ATR × 1.5–2.0 uzaklığında (volatiliteye uyumlu)
        • **Teknik seviye bazlı**: Destek kırılırsa kapatıyorum (örn. MA50 altı)
        • **Swing low altı**: Son önemli dibin biraz altı

        **Önemli noktalar:**
        • Stop-loss güvenlik ağıdır; doğru fiyat belirlenmesi kritiktir
        • Çok dar stop → normal dalgalanmada tetiklenebilir
        • Çok geniş stop → risk/getiri oranı bozulabilir

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func trailingStopExplain() -> String {
        """
        **Trailing Stop (İzleyen Stop)**

        Trailing stop, fiyat yükseldikçe stop seviyesini de otomatik olarak yukarı taşıyan dinamik bir stop türüdür.

        **Nasıl çalışır?**
        Örnek: %10 trailing stop
        • Fiyat 100 ₺ → stop 90 ₺
        • Fiyat 120 ₺'ye yükseldi → stop 108 ₺'ye taşındı
        • Fiyat 108 ₺'ye geri geldi → pozisyon kapatıldı

        **Avantajı:**
        • Yükseliş trendinde kâr korur
        • Manuel müdahale gerektirmez

        **Dezavantajı:**
        • Yüksek volatilite ortamında çok erken tetiklenebilir
        • Destek/direnç seviyelerini dikkate almaz

        Stop-loss vs Trailing stop: Sabit stop zarar sınırlar, trailing stop kârı korur.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func riskReturnExplain() -> String {
        """
        **Risk/Getiri Oranı (Risk-Return Ratio)**

        Risk/Getiri oranı, bir işlemde beklenen kazancın üstlenilen riske oranıdır.

        **Formül:**
        Risk/Getiri = Potansiyel Kazanç ÷ Potansiyel Kayıp

        **Örnek:**
        • Giriş: 100 ₺ · Stop-loss: 95 ₺ (5 ₺ risk)
        • Hedef: 115 ₺ (15 ₺ potansiyel kazanç)
        • Risk/Getiri = 15 ÷ 5 = **3:1** (her 1 TL riske karşı 3 TL potansiyel kazanç)

        **Genel kural:**
        • **1:1** → minimum kabul edilebilir (eşit risk/kazanç)
        • **2:1** → iyi
        • **3:1 ve üzeri** → güçlü

        Gerçek Risk/Getiri, kazanma olasılığıyla (win rate) birlikte değerlendirilmelidir:
        Düşük win rate + yüksek R/R oranı yine kârlı olabilir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func longPositionExplain() -> String {
        """
        **Uzun Pozisyon (Long)**

        Uzun pozisyon (long), bir varlığı satın alarak fiyatının yükseleceğini öngörme stratejisidir.

        **Nasıl çalışır?**
        1. Hisseyi şu fiyattan satın al
        2. Fiyat yükselirse yüksek fiyattan sat → kâr
        3. Fiyat düşerse düşük fiyattan sat → zarar

        **Maksimum kayıp:** Yatırılan tutar (hisse sıfıra düşerse)
        **Maksimum kazanç:** Teorik olarak sınırsız (fiyat sonsuza çıkabilir)

        BIST'teki standart işlem türüdür — çoğu bireysel yatırımcı long pozisyon alır.

        **Kısa pozisyon (short) ile farkı:**
        Short → fiyatın düşeceği beklentisiyle önce sat, sonra al. BIST'te açığa satış belirli kısıtlara tabidir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func shortSellingExplain() -> String {
        """
        **Açığa Satış (Short Selling)**

        Açığa satış, sahip olmadığın hisseyi ödünç alarak satmak ve daha düşük fiyattan geri almaktır.

        **Nasıl çalışır?**
        1. Hisseyi 100 ₺'den ödünç sat
        2. Fiyat 80 ₺'ye düştü → 80 ₺'den geri al
        3. Kâr: 20 ₺ (komisyon ve ödünç maliyeti hariç)

        **Riskler:**
        • **Teorik sınırsız kayıp**: Fiyat yükselirse kayıp sınırsız büyür
        • **Short squeeze**: Çok kişi short yaptıysa ani alım baskısı fiyatı patlatabilir
        • **Ödünç maliyeti**: Hisse ödünç almak maliyetlidir

        **BIST'te durum:**
        Açığa satış BIST'te belirli düzenlemelere tabidir; tüm hisseler açığa satışa açık değildir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func dcaExplain() -> String {
        """
        **DCA — Dollar-Cost Averaging (Periyodik Yatırım)**

        DCA, belirli aralıklarla sabit miktarda yatırım yapma stratejisidir. Fiyattan bağımsız düzenli alım.

        **Nasıl çalışır?**
        Her ay 1.000 ₺ yatırım yapıyorsun:
        • Fiyat yüksekse → daha az hisse alırsın
        • Fiyat düşükse → daha fazla hisse alırsın
        Sonuç: Ortalama maliyet, en yüksek noktadan daha düşük olur.

        **Avantajları:**
        • "Dip bulmak" zorunda değilsiniz
        • Duygusal kararları azaltır
        • Düşüş dönemlerinde daha fazla hisse biriktirilir

        **Dezavantajı:**
        • Sürekli yükselen piyasada toplu alıma göre daha az verimli olabilir
        • Komisyonlar maliyet yaratabilir

        Uzun vadeli birikim stratejilerinde yaygın kullanılır.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func swingTradingExplain() -> String {
        """
        **Swing Trading**

        Swing trading, birkaç gün ila birkaç hafta içinde fiyat "salınımlarından" kâr etmeyi hedefleyen stratejidir.

        **Gün içi işlemden (day trading) farkı:**
        • Day trading: Aynı gün aç–kapat
        • Swing trading: Günler/haftalar boyunca pozisyon tut
        • Pozisyon trading: Aylar/yıllar boyunca tut

        **Temel araçlar:**
        • Destek/direnç seviyeleri
        • Trend çizgileri
        • RSI, MACD gibi momentum göstergeleri
        • Mum formasyonları

        **Risk faktörleri:**
        • Gece/hafta sonu tutma riski (haberler, gap açılışlar)
        • Disiplin gerektirir — stop-loss ve hedef fiyat önceden belirlenmeli

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func momentumTradingExplain() -> String {
        """
        **Momentum Trading**

        Momentum stratejisi, güçlü trend gösteren varlıkların bir süre daha aynı yönde hareket edeceği varsayımına dayanır.

        **Temel fikir:**
        "Yükselen yükselmeye, düşen düşmeye devam eder" — en azından kısa vadede.

        **Kullanılan göstergeler:**
        • RSI (aşırı alım/satım bölgelerinden kaçınılır, güçlü bölge tercih edilir)
        • MACD histogram genişlemesi
        • Hacim artışı (momentumu teyit eder)
        • Rate of Change (ROC)

        **Riskler:**
        • Trend aniden tersine dönebilir
        • "Geç kalmak" maliyetli olabilir — fiyat zaten çok yükselmişse risk artar
        • Yatay piyasalarda çalışmaz

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func positionSizingExplain() -> String {
        """
        **Pozisyon Boyutlandırma**

        Pozisyon boyutu, tek bir işleme ne kadar sermaye ayıracağınızı belirler.

        **Yaygın yöntemler:**

        **1. Sabit yüzde yöntemi:**
        Her işlemde toplam sermayenin %2'sini riske at.
        Örnek: 100.000 ₺ sermaye → işlem başına max 2.000 ₺ risk

        **2. ATR bazlı yöntem:**
        Pozisyon büyüklüğü = Risk miktarı ÷ (ATR × çarpan)
        Volatil hisselerde otomatik olarak daha küçük pozisyon

        **3. Kelly Kriteri:**
        Matematiksel formülle optimal pozisyon hesabı (win rate ve R/R oranına göre)

        **Temel kural:**
        Tek bir işlemde toplam sermayenin %1–5'inden fazlasını riske etmemek yaygın bir risk yönetimi yaklaşımıdır.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func techVsFundamentalExplain() -> String {
        """
        **Teknik Analiz mi, Temel Analiz mi?**

        Her ikisi de farklı soruları yanıtlar:

        **Teknik Analiz:**
        "Piyasa şu anda ne yapıyor? Momentum nereye?"
        • Kısa/orta vadeli zamanlama için kullanılır
        • Fiyat ve hacim verisi yeterli — bilanço gerekmez
        • Kendi kendini gerçekleştiren kehanet etkisi (çok kişi aynı seviyelere bakıyor)

        **Temel Analiz:**
        "Bu şirket değerinin altında mı üstünde mi?"
        • Uzun vadeli değer yatırımcıları için
        • Bilanço, kâr büyümesi, yönetim kalitesi incelenir
        • Piyasanın "yanlış fiyatlamasını" bulmaya çalışır

        **Pratikte:**
        Çoğu profesyonel her ikisini birleştirir:
        → Temel analiz ile doğru şirket, teknik analiz ile doğru zamanlama.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func marketRiskExplain() -> String {
        """
        **Piyasa Riski Türleri**

        **1. Sistematik Risk (Piyasa Riski):**
        Tüm piyasayı etkileyen riskler — çeşitlendirme ile elimine edilemez.
        • Faiz riski: Merkez bankası kararları
        • Kur riski: TL değer kaybı/kazancı
        • Enflasyon riski: Reel getiriyi aşındırır
        • Jeopolitik risk: Siyasi gelişmeler

        **2. Sistematik Olmayan Risk (Şirket Riski):**
        Tek bir şirkete özgü riskler — çeşitlendirme ile azaltılabilir.
        • Yönetim riski
        • Sektör riski
        • Bilanço riski

        **3. Likidite Riski:**
        İstenen fiyattan çıkamama riski — özellikle küçük ve orta ölçekli hisseler.

        **Risk yönetimi araçları:**
        • Çeşitlendirme · Stop-loss · Pozisyon boyutu · Vade çeşitlendirmesi

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func stockExplain() -> String {
        """
        **Hisse Senedi Nedir?**

        Hisse senedi, bir şirkete ortak olma hakkını temsil eden menkul kıymettir.

        **Temel haklar:**
        • **Kâr payı (temettü)**: Şirket kâr dağıtırsa pay alırsın
        • **Oy hakkı**: Genel kurulda oy kullanma hakkı (hisse türüne göre)
        • **Tasfiye hakkı**: Şirket kapanırsa varlıklardan pay

        **BIST'te hisse türleri:**
        • **A grubu**: Oy hakkı imtiyazlı
        • **B, C grubu**: Standart oy hakkı
        • **Paylar**: Her hisse bir payı temsil eder

        **Fiyatı ne belirler?**
        Arz ve talep — şirket performansı, sektör beklentileri, makroekonomik faktörler ve piyasa duyarlılığı fiyatı etkiler.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func lotExplain() -> String {
        """
        **Lot Nedir?**

        BIST'te hisse senetleri **lot** birimi ile işlem görür.

        **1 lot = 1 hisse senedi** (BIST'te standart birim)

        Bazı eski düzenlemelerde 1 lot = 100 hisse idi; 2014'te yapılan reformla 1 lot = 1 hisse olarak güncellendi.

        **İşlem büyüklüğü:**
        • Minimum işlem: 1 lot (= 1 hisse × hisse fiyatı)
        • Örnek: THYAO fiyatı 250 ₺ ise 1 lot alım = 250 ₺

        **Paylı alım:**
        BIST'te kesirli lot alımı yapılamaz — tamsayı lot ile işlem zorunludur.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func ipoExplain() -> String {
        """
        **Halka Arz (IPO)**

        Halka arz (Initial Public Offering), bir şirketin hisselerini ilk kez halka sunmasıdır.

        **Süreç:**
        1. Şirket aracı kurum ile çalışır
        2. SPK (Sermaye Piyasası Kurulu) onayı alınır
        3. İzahname yayımlanır — şirket hakkında detaylı bilgi
        4. Halka arz fiyatı belirlenir (kitap yapım süreci)
        5. Yatırımcılar talep bildirir — talep fazlaysa kısmi dağıtım
        6. Hisse borsada işlem görmeye başlar

        **BIST'te halka arzlara nasıl katılınır?**
        Aracı kurum üzerinden elektronik talep bildirimi yapılır.

        **Riskler:**
        • Halka arz fiyatı yüksek belirlenmiş olabilir
        • İlk işlem günü büyük fiyat dalgalanması olabilir
        • Şirketin geçmiş performansı sınırlı olabilir

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func currencyEffectExplain() -> String {
        """
        **Döviz Kurlarının Hisse Senetlerine Etkisi**

        Döviz kuru değişimleri farklı şirketleri farklı etkiler:

        **TL değer kaybettiğinde (dolar/euro yükselir):**
        ✅ Kazananlar:
        • İhracatçılar (THYAO, EREGL, TUPRS) — TL gelir artar
        • Döviz aktifi olan holding şirketleri
        ❌ Kaybedenler:
        • İthalatçılar — ham madde maliyeti artar
        • Döviz borçlu şirketler — borç yükü TL olarak artar
        • Yurt içi perakende (BIMAS, MGROS) — maliyet baskısı

        **TL değer kazandığında:** Tam tersi etki.

        **BIST genel olarak:**
        Yabancı yatırımcı girişi = dolar → TL dönüşümü = TL'ye talep = BIST'e pozitif etki.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func inflationEffectExplain() -> String {
        """
        **Enflasyonun Hisse Senetlerine Etkisi**

        Yüksek enflasyon ortamında hisse senetleri farklı şekillerde etkilenir:

        **Olumlu etkiler:**
        • Şirketlerin stok/varlık değerleri artar
        • Fiyatlama gücü olan şirketler (BIMAS, MGROS) maliyet artışını fiyata yansıtabilir
        • Enflasyona göre endekslenmiş gelirleri olan şirketler korunur

        **Olumsuz etkiler:**
        • Faiz artışına yol açar → hisse değerlemelerini baskılar
        • Tüketici harcamasını kısar → gelir büyümesi yavaşlayabilir
        • Maliyet baskısı kâr marjlarını eritebilir

        **Enflasyon ortamında öne çıkabilecek sektörler (eğitsel):**
        Enerji · Ham madde · Gayrimenkul · İhracatçılar

        Gerçek yatırım kararları için uzman görüşü alınmalıdır.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func interestRateEffectExplain() -> String {
        """
        **Faiz Oranlarının Borsaya Etkisi**

        Merkez Bankası faiz kararları hisse senetlerini doğrudan ve dolaylı etkiler:

        **Faiz artışı:**
        • Bono/mevduat faizi cazip hale gelir → hisseden fona para çıkışı olabilir
        • Şirketlerin borçlanma maliyeti artar → kâr baskılanabilir
        • Hisse değerleme çarpanları (F/K) baskılanır
        • Borçlu şirketler (yüksek D/E) daha çok etkilenir

        **Faiz indirimi:**
        • Alternatiflere göre hisse cazip hale gelir → fon girişi
        • Şirketlerin kredi maliyeti düşer
        • Değerleme çarpanları genişler

        **Bankacılık sektörü özel durumu:**
        Faiz artışı kısa vadede banka net faiz marjını olumlu etkileyebilir, ancak kredi kalitesi bozulabilir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func globalMarketsExplain() -> String {
        """
        **Küresel Piyasaların BIST'e Etkisi**

        BIST, küresel piyasalarla korelasyon içindedir — özellikle risk iştahı değişimlerinde.

        **ABD piyasaları (S&P 500, Nasdaq, Dow Jones):**
        • Küresel risk iştahının temel göstergesi
        • Düşüşler gelişmekte olan piyasalara (EM) satış dalgası yaratabilir
        • BIST de EM kategorisinde → ABD negatif = BIST'e yabancı satışı riski

        **Gelişmekte olan piyasalar (EM) endeksi:**
        Yabancı yatırımcılar BIST'i EM portföyü içinde değerlendirir.

        **Emtia fiyatları:**
        • Petrol yükselişi → enerji hisseleri olumlu (TUPRS, AYGAZ)
        • Çelik/metal yükselişi → EREGL, KRDMD gibi şirketler

        **Fed kararları:**
        Dolar güçlenirse EM'den çıkış yaşanabilir — BIST'te yabancı satışı.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func marketHoursExplain() -> String {
        """
        **BIST İşlem Saatleri**

        **Pay Piyasası (Hisse Senetleri):**
        • Sürekli müzayede öncesi: **09:40 – 09:55** (emir girilir, işlem olmaz)
        • Sürekli müzayede: **10:00 – 18:00**
        • Kapanış fiyatı seansı: **18:00 – 18:10**

        **Pazartesi – Cuma** (resmi tatiller hariç)

        **VİOP (Vadeli İşlem ve Opsiyon Piyasası):**
        09:00 – 18:15

        **Takas:**
        • Hisse senetleri: T+2 (işlem günü + 2 iş günü)
        • Nakit takası aynı gün gerçekleşir

        **Dikkat:** Gün içi fiyat değişkenliği en yüksek açılış ve kapanış saatlerinde görülür.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func circuitBreakerExplain() -> String {
        """
        **Devre Kesici (Circuit Breaker)**

        Devre kesici, aşırı fiyat dalgalanmalarını durdurmak için tasarlanmış otomatik mekanizmadır.

        **BIST'te uygulama:**
        • Tek bir hissede **±%10 fiyat değişimi** → o hisse için 30 dakika işlem durdurulur
        • Tekrar açıldıktan sonra sınır ±%15'e genişler
        • Endeks bazında da genel devre kesiciler mevcuttur

        **Neden var?**
        • Panik satışlarının zincirleme etkisini kırmak
        • Yatırımcılara durumu değerlendirme süresi vermek
        • Olağandışı haberlerin ani etkisini yumuşatmak

        **Dikkat:**
        Devre kesici bir hissenin iyi ya da kötü olduğu anlamına gelmez; sadece fiyat hareketi eşiği aşıldı demektir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func newsEffectExplain() -> String {
        """
        **Haberlerin Hisse Fiyatına Etkisi**

        Şirket haberleri anlık ve güçlü fiyat hareketleri yaratabilir.

        **Olumlu haber örnekleri:**
        • Beklentilerin üzerinde kâr açıklaması
        • Büyük sözleşme/ihracat haberi
        • Temettü artışı duyurusu
        • Kurumsal alım / ortaklık anlaşması

        **Olumsuz haber örnekleri:**
        • Beklentinin altında kâr
        • Yönetim değişikliği (belirsizlik)
        • Regülasyon/ceza haberleri
        • Dava açılması

        **KAP (Kamuyu Aydınlatma Platformu):**
        BIST şirketleri önemli gelişmeleri KAP'a bildirmek zorundadır (kap.org.tr).

        **Dikkat:** Haber beklentisi fiyata önceden yansımış olabilir — "söylenti alınır, haber satılır" piyasa deyimidir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    private func bist3050Explain() -> String {
        """
        **BIST 30 ve BIST 50 Endeksleri**

        **BIST 30 (XU030):**
        BIST'in en likit ve en büyük 30 şirketini içerir.
        • Vadeli işlem ve opsiyon kontratlarının dayanak varlığı
        • Kurumsal yatırımcıların en çok takip ettiği endeks
        • Örnek bileşenler: THYAO, GARAN, AKBNK, EREGL, SISE, KCHOL

        **BIST 50 (XU050):**
        En büyük 50 şirketi içerir — BIST 30'u kapsar + 20 şirket daha.

        **BIST 100 ile farkı:**
        • BIST 30: Dar, likit, kurumsal odak
        • BIST 100: Geniş, piyasanın genel yönünü gösterir
        • Küçük/orta ölçekli hisseler genellikle BIST 100'de ama BIST 30/50'de değil

        **Endeks yenileme:**
        Her 3 ayda bir yeniden değerlendirme yapılır; şirketler giriş/çıkış yaşayabilir.

        **Bu bir yatırım tavsiyesi değildir.**
        """
    }

    // MARK: - Helpers
    private func rsiInterpret(_ rsi: Double) -> String {
        switch rsi {
        case ..<25:  return "Güçlü aşırı satım"
        case ..<35:  return "Aşırı satım bölgesi"
        case ..<50:  return "Nötr — zayıf taraf"
        case ..<65:  return "Nötr — güçlü taraf"
        case ..<75:  return "Aşırı alım bölgesine yakın"
        default:     return "Güçlü aşırı alım bölgesi"
        }
    }

    private func volInterpret(_ vol: Double) -> String {
        switch vol {
        case ..<25:  return "Düşük oynaklık"
        case ..<50:  return "Orta oynaklık"
        case ..<75:  return "Yüksek oynaklık"
        default:     return "Çok yüksek oynaklık"
        }
    }

    // MARK: - Sector Query Handler (async – needs live data)

    // Known BIST sector keywords → canonical sector names
    private static let sectorKeywords: [(keyword: String, name: String)] = [
        ("bankacılık", "Bankacılık"),
        ("banka", "Bankacılık"),
        ("enerji", "Enerji"),
        ("teknoloji", "Teknoloji"),
        ("sanayi", "Sanayi"),
        ("perakende", "Perakende"),
        ("gayrimenkul", "Gayrimenkul"),
        ("inşaat", "Gayrimenkul"),
        ("savunma", "Savunma"),
        ("gıda", "Gıda"),
        ("iletişim", "İletişim"),
        ("telekom", "İletişim"),
        ("ulaşım", "Ulaşım"),
        ("havacılık", "Ulaşım"),
        ("otomotiv", "Otomotiv"),
        ("madencilik", "Madencilik"),
        ("sigorta", "Sigorta"),
        ("holding", "Holding"),
        ("sağlık", "Sağlık"),
        ("spor", "Spor"),
        ("turizm", "Turizm"),
        ("kimya", "Kimya"),
        ("tekstil", "Tekstil"),
    ]

    private func handleSectorQuery(query: String) async -> String? {
        let q = query.lowercased()
        guard q.contains("sektör") || q.contains("sector") ||
              AssistantEngine.sectorKeywords.contains(where: { q.contains($0.keyword) })
        else { return nil }

        // Find which sector keyword was mentioned
        var matchedSector: String? = nil
        for pair in AssistantEngine.sectorKeywords {
            if q.contains(pair.keyword) {
                matchedSector = pair.name
                break
            }
        }

        // Genel sektör sorusu: tüm sektörleri listele
        guard let sectorName = matchedSector else {
            return await allSectorsSummary()
        }

        // Belirli bir sektör
        return await sectorSummaryResponse(sectorName: sectorName)
    }

    private func allSectorsSummary() async -> String {
        guard let sectors = try? await quoteRepository?.sectors(), !sectors.isEmpty else {
            return """
            **BIST Sektörleri**

            Başlıca BIST sektörleri: Bankacılık, Enerji, Teknoloji, Sanayi, Perakende, Gayrimenkul, Savunma, Gıda, İletişim, Ulaşım, Otomotiv, Madencilik, Sigorta, Holding, Sağlık, Turizm.

            Belirli bir sektör hakkında bilgi almak için "Bankacılık sektörü nasıl?" gibi soru sorabilirsin.

            **Bu bir yatırım tavsiyesi değildir.**
            """
        }

        let sorted = sectors.sorted { abs($0.changePercent) > abs($1.changePercent) }
        let gainers = sorted.filter { $0.changePercent >= 0 }
        let losers  = sorted.filter { $0.changePercent < 0 }

        var lines: [String] = ["## Sektör Performansı\n"]
        lines.append("**Yükselen Sektörler:**")
        for s in gainers.prefix(5) {
            lines.append("• \(s.name): **+\(String(format: "%.2f%%", s.changePercent))**")
        }
        if !losers.isEmpty {
            lines.append("\n**Düşen Sektörler:**")
            for s in losers.prefix(5) {
                lines.append("• \(s.name): **\(String(format: "%.2f%%", s.changePercent))**")
            }
        }
        if let best = sorted.first(where: { $0.changePercent >= 0 }) {
            lines.append("\n**En İyi Sektör:** \(best.name) (\(best.formattedChange))")
        }
        if let worst = sorted.last {
            lines.append("**En Kötü Sektör:** \(worst.name) (\(worst.formattedChange))")
        }
        lines.append("\n**Bu bir yatırım tavsiyesi değildir.**")
        return lines.joined(separator: "\n")
    }

    private func sectorSummaryResponse(sectorName: String) async -> String {
        guard let sectors = try? await quoteRepository?.sectors(),
              let sector = sectors.first(where: {
                  $0.name.lowercased().contains(sectorName.lowercased()) ||
                  sectorName.lowercased().contains($0.name.lowercased())
              })
        else {
            return """
            **\(sectorName) Sektörü**

            Bu sektöre ait güncel veri şu an alınamadı. Piyasa ekranındaki sektör şeridine dokunarak detaylarını görebilirsin.

            **Bu bir yatırım tavsiyesi değildir.**
            """
        }

        let direction = sector.changePercent >= 0 ? "yükseliş" : "düşüş"
        let emoji     = sector.changePercent >= 0 ? "📈" : "📉"
        var lines: [String] = ["\(emoji) **\(sector.name) Sektörü**\n"]
        lines.append("**Günlük Değişim:** \(sector.formattedChange)")
        lines.append("**Hisse Sayısı:** \(sector.stockCount)")

        if let topGainer = sector.topGainer {
            lines.append("**Öncü Hisse:** \(topGainer)")
        }

        let mood = sector.changePercent > 2   ? "güçlü alım baskısı görülüyor" :
                   sector.changePercent > 0   ? "hafif pozitif seyir" :
                   sector.changePercent > -2  ? "hafif satış baskısı" :
                                               "belirgin satış baskısı"
        lines.append("\nSektörde bugün **\(direction)** eğilimi hakim; \(mood).")

        if sector.changePercent.magnitude < 0.5 {
            lines.append("Sektör görece yatay seyrediyor.")
        }

        lines.append("\n_Detaylı analiz için Piyasa ekranındaki sektör kartına dokunabilirsin._")
        lines.append("\n**Bu bir yatırım tavsiyesi değildir.**")
        return lines.joined(separator: "\n")
    }
}
