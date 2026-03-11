// ContextBuilder.swift – Builds structured context for AssistantEngine
// BIST Radar AI

import Foundation

struct AssistantContext: Sendable {
    let symbol: String?
    let quote: Quote?
    let candles: [Candle]
    let fundamentals: Fundamentals?
    let snapshot: IndicatorSnapshot?
    let insights: [Insight]
    let fetchedAt: Date

    var hasData: Bool { quote != nil || !candles.isEmpty }

    var textSummary: String {
        guard let sym = symbol else {
            return "Genel piyasa bağlamı. Sembol seçilmedi."
        }

        var parts: [String] = ["Sembol: \(sym)"]

        if let q = quote {
            parts.append("Fiyat: \(q.formattedPrice) (\(q.formattedChange) günlük)")
            if q.isDelayed { parts.append("[VERİ GECİKMELİ]") }
        } else {
            parts.append("Fiyat verisi mevcut değil.")
        }

        if let s = snapshot {
            if let rsi = s.rsi14 { parts.append("RSI(14)=\(String(format: "%.1f", rsi))") }
            if let sma20 = s.sma20 { parts.append("MA20=\(String(format: "%.2f", sma20))") }
            if let sma50 = s.sma50 { parts.append("MA50=\(String(format: "%.2f", sma50))") }
            if let vol = s.volatilityScore { parts.append("Volatilite=\(String(format: "%.0f", vol))/100") }
            if let vanom = s.volumeAnomalyPct { parts.append("Hacim=%\(String(format: "%.0f", vanom)) (20g ort.)") }
            if let c7 = s.change7d { parts.append("7g=%\(String(format: "%.1f", c7))") }
            if let c30 = s.change30d { parts.append("30g=%\(String(format: "%.1f", c30))") }
            if s.isUnusualMove, let sigma = s.unusualMoveSigma {
                parts.append("Olağandışı hareket: \(String(format: "%.1f", sigma))σ")
            }
        }

        if let f = fundamentals {
            if let pe = f.peRatio { parts.append("F/K=\(String(format: "%.1f", pe))") }
            if let pb = f.pbRatio { parts.append("PD/DD=\(String(format: "%.2f", pb))") }
        }

        return parts.joined(separator: " | ")
    }

    /// Extended summary including MACD, Bollinger, EMA, support/resistance – used by LLM context.
    var richTextSummary: String {
        guard let sym = symbol else {
            return "Genel piyasa bağlamı. Sembol seçilmedi."
        }

        var lines: [String] = []
        lines.append("════════════════════════════════")
        lines.append("HİSSE: \(sym)")
        lines.append("════════════════════════════════")

        // Fiyat & Günlük Değişim
        if let q = quote {
            lines.append("Güncel Fiyat: \(q.formattedPrice)")
            lines.append("Günlük Değişim: \(q.formattedChange)")
            if q.open > 0    { lines.append("Açılış: \(String(format: "%.2f", q.open)) ₺") }
            if q.high > 0    { lines.append("Gün İçi Yüksek: \(String(format: "%.2f", q.high)) ₺") }
            if q.low > 0     { lines.append("Gün İçi Düşük: \(String(format: "%.2f", q.low)) ₺") }
            if q.volume > 0  { lines.append("Hacim: \(String(format: "%.0f", q.volume)) lot") }
            if q.volumeTL > 0 { lines.append("İşlem Hacmi: \(String(format: "%.0f", q.volumeTL / 1_000_000)) M ₺") }
        } else {
            lines.append("Fiyat: Mevcut değil")
        }

        if let s = snapshot {
            lines.append("")
            lines.append("── PERFORMANS ──")
            if let c7  = s.change7d  { lines.append("7 Günlük: \(c7  >= 0 ? "+" : "")\(String(format: "%.2f", c7))%") }
            if let c30 = s.change30d { lines.append("30 Günlük: \(c30 >= 0 ? "+" : "")\(String(format: "%.2f", c30))%") }

            lines.append("")
            lines.append("── MOMENTUM GÖSTERGELERİ ──")
            if let rsi = s.rsi14 {
                let zone = rsi < 30 ? "AŞIRI SATIM" : rsi < 50 ? "ZAYIF" : rsi < 70 ? "GÜÇLÜ" : "AŞIRI ALIM"
                lines.append("RSI(14)=\(String(format: "%.2f", rsi)) [\(zone)]")
            }
            if let macd = s.macd, let sig = s.macdSignal, let hist = s.macdHistogram {
                let signal = hist > 0 ? "YÜKSELİŞ" : "DÜŞÜŞ"
                let aboveZero = macd > 0 ? "Sıfır üstü" : "Sıfır altı"
                lines.append("MACD=\(String(format: "%.4f", macd)) [\(aboveZero), \(signal) momentum]")
                lines.append("MACD Sinyal=\(String(format: "%.4f", sig))")
                lines.append("MACD Histogram=\(String(format: "%.4f", hist))")
            }
            if let stoch = s.stochRSI {
                let zone = stoch > 80 ? "AŞIRI ALIM" : stoch < 20 ? "AŞIRI SATIM" : "NÖTR"
                lines.append("StochRSI=\(String(format: "%.1f", stoch)) [\(zone)]")
            }

            lines.append("")
            lines.append("── HAREKETLİ ORTALAMALAR ──")
            let lastPrice = quote?.lastPrice ?? 0
            if let sma20 = s.sma20 {
                let dir = lastPrice > sma20 ? "üzerinde" : "altında"
                lines.append("SMA20=\(String(format: "%.2f", sma20)) ₺ [Fiyat \(dir)]")
            }
            if let sma50 = s.sma50 {
                let dir = lastPrice > sma50 ? "üzerinde" : "altında"
                lines.append("SMA50=\(String(format: "%.2f", sma50)) ₺ [Fiyat \(dir)]")
            }
            if let ema20 = s.ema20 {
                let dir = lastPrice > ema20 ? "üzerinde" : "altında"
                lines.append("EMA20=\(String(format: "%.2f", ema20)) ₺ [Fiyat \(dir)]")
            }
            if let ema50 = s.ema50 {
                let dir = lastPrice > ema50 ? "üzerinde" : "altında"
                lines.append("EMA50=\(String(format: "%.2f", ema50)) ₺ [Fiyat \(dir)]")
            }
            if let e20 = s.ema20, let e50 = s.ema50 {
                lines.append("EMA20 vs EMA50: \(e20 > e50 ? "EMA20 > EMA50 (yükselen eğilim)" : "EMA20 < EMA50 (düşen eğilim)")")
            }

            lines.append("")
            lines.append("── BOLLINGER BANTLARI ──")
            if let bU = s.bollingerUpper, let bM = s.bollingerMiddle,
               let bL = s.bollingerLower, let bw = s.bollingerBandwidth,
               let pctB = s.bollingerPercentB {
                lines.append("Üst Band=\(String(format: "%.2f", bU)) ₺")
                lines.append("Orta (SMA20)=\(String(format: "%.2f", bM)) ₺")
                lines.append("Alt Band=\(String(format: "%.2f", bL)) ₺")
                lines.append("Band Genişliği=\(String(format: "%.2f", bw))% [\(bw < 10 ? "SIKIŞMA" : bw < 20 ? "DAR" : "NORMAL")]")
                let pctBLabel = pctB > 80 ? "Üst banda yakın" : pctB < 20 ? "Alt banda yakın" : "Orta bölge"
                lines.append("%B=\(String(format: "%.1f", pctB)) [\(pctBLabel)]")
            }

            lines.append("")
            lines.append("── VOLATİLİTE & HACİM ──")
            if let vol = s.volatilityScore {
                let lvl = vol < 25 ? "DÜŞÜK" : vol < 50 ? "ORTA" : vol < 75 ? "YÜKSEK" : "ÇOK YÜKSEK"
                lines.append("Volatilite=\(String(format: "%.0f", vol))/100 [\(lvl)]")
            }
            if let vanom = s.volumeAnomalyPct {
                let lvl = vanom > 200 ? "ÇARPICI ARTIŞI" : vanom > 150 ? "YÜKSEK" : vanom < 50 ? "DÜŞÜK" : "NORMAL"
                lines.append("Hacim=\(String(format: "%.0f", vanom))% (20g ort.) [\(lvl)]")
            }
            if s.isUnusualMove, let sigma = s.unusualMoveSigma {
                lines.append("⚠️ Olağandışı hareket: \(String(format: "%.1f", sigma))σ")
            }
        }

        // Destek / Direnç
        if !candles.isEmpty, let sr = SupportResistanceCalculator.compute(candles: candles) {
            lines.append("")
            lines.append("── DESTEK / DİRENÇ ──")
            if !sr.resistances.isEmpty {
                lines.append("Direnç: " + sr.resistances.map { String(format: "%.2f ₺", $0) }.joined(separator: " | "))
            }
            if !sr.supports.isEmpty {
                lines.append("Destek: " + sr.supports.map { String(format: "%.2f ₺", $0) }.joined(separator: " | "))
            }
            lines.append("Pivot=\(String(format: "%.2f", sr.pivotPoint)) | R1=\(String(format: "%.2f", sr.r1)) | R2=\(String(format: "%.2f", sr.r2)) | S1=\(String(format: "%.2f", sr.s1)) | S2=\(String(format: "%.2f", sr.s2))")
        }

        // Temel Analiz
        if let f = fundamentals {
            lines.append("")
            lines.append("── TEMEL ANALİZ ──")
            if let pe = f.peRatio        { lines.append("F/K (P/E)=\(String(format: "%.2f", pe))") }
            if let pb = f.pbRatio        { lines.append("PD/DD (P/B)=\(String(format: "%.2f", pb))") }
            if let ev = f.evEbitda       { lines.append("EV/EBITDA=\(String(format: "%.2f", ev))") }
            if let dy = f.dividendYield  { lines.append("Temettü Verimi=\(String(format: "%.2f", dy))%") }
            if let nm = f.netMargin      { lines.append("Net Kar Marjı=\(String(format: "%.1f", nm))%") }
            if let roe = f.roe           { lines.append("ROE=\(String(format: "%.1f", roe))%") }
            if let roa = f.roa           { lines.append("ROA=\(String(format: "%.1f", roa))%") }
            if let de = f.debtToEquity   { lines.append("Borç/Özsermaye=\(String(format: "%.2f", de))") }
            if let cr = f.currentRatio   { lines.append("Cari Oran=\(String(format: "%.2f", cr))") }
            if let rg = f.revenueGrowthYoY { lines.append("Gelir Büyümesi (YoY)=\(String(format: "%.1f", rg))%") }
            if let ig = f.netIncomeGrowthYoY { lines.append("Net Kar Büyümesi (YoY)=\(String(format: "%.1f", ig))%") }
        }

        // Kural motoru sinyalleri
        if !insights.isEmpty {
            lines.append("")
            lines.append("── KURAL TABANLI SİNYALLER ──")
            for insight in insights {
                let icon = insight.severity == .warning ? "⚠️" : insight.severity == .info ? "ℹ️" : "•"
                lines.append("\(icon) \(insight.title): \(insight.numericEvidence)")
            }
        }

        lines.append("")
        lines.append("Veri zamanı: \(ISO8601DateFormatter().string(from: fetchedAt))")
        lines.append("Mum verisi: \(candles.count) günlük (3 aylık)")
        return lines.joined(separator: "\n")
    }
}

@MainActor
final class ContextBuilder {
    private let quoteRepository: QuoteRepository
    private let insightEngine: RuleInsightEngine

    init(quoteRepository: QuoteRepository, insightEngine: RuleInsightEngine) {
        self.quoteRepository = quoteRepository
        self.insightEngine = insightEngine
    }

    func build(symbol: String?) async -> AssistantContext {
        guard let symbol = symbol, !symbol.isEmpty else {
            return AssistantContext(
                symbol: nil, quote: nil, candles: [], fundamentals: nil,
                snapshot: nil, insights: [], fetchedAt: Date()
            )
        }

        async let quoteTask    = try? quoteRepository.quote(for: symbol)
        async let candlesTask  = try? quoteRepository.candles(symbol: symbol, timeframe: .threeMonths)
        async let fundaTask    = try? quoteRepository.fundamentals(symbol: symbol)

        let (quote, candles, fundamentals) = await (quoteTask, candlesTask, fundaTask)

        let safeCandles = candles ?? []
        let snapshot = safeCandles.count >= 15
            ? insightEngine.buildSnapshot(symbol: symbol, candles: safeCandles)
            : nil
        let insights = snapshot.map { insightEngine.generateInsights(snapshot: $0, candles: safeCandles) } ?? []

        return AssistantContext(
            symbol: symbol,
            quote: quote,
            candles: safeCandles,
            fundamentals: fundamentals,
            snapshot: snapshot,
            insights: insights,
            fetchedAt: Date()
        )
    }
}
