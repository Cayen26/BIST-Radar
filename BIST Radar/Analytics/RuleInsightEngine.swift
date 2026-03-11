// RuleInsightEngine.swift – Turkish educational rule-based insights
// BIST Radar AI
// NON-NEGOTIABLE: Never recommend buy/sell. Always cite numeric evidence.

import Foundation

final class RuleInsightEngine: Sendable {

    // MARK: - Main entry point
    func generateInsights(
        snapshot: IndicatorSnapshot,
        candles: [Candle]
    ) -> [Insight] {
        var insights: [Insight] = []

        insights.append(contentsOf: performanceInsights(snapshot: snapshot))
        insights.append(contentsOf: rsiInsight(snapshot: snapshot))
        insights.append(contentsOf: movingAvgInsights(snapshot: snapshot, candles: candles))
        insights.append(contentsOf: macdInsight(snapshot: snapshot))
        insights.append(contentsOf: bollingerInsight(snapshot: snapshot))
        insights.append(contentsOf: volumeInsight(snapshot: snapshot))
        insights.append(contentsOf: volatilityInsight(snapshot: snapshot))
        insights.append(contentsOf: unusualMoveInsight(snapshot: snapshot))

        return insights
    }

    // MARK: - Full text for assistant output
    func fullInsightText(snapshot: IndicatorSnapshot, candles: [Candle]) -> String {
        let insights = generateInsights(snapshot: snapshot, candles: candles)
        let lines = insights.map { "• \($0.body)" }
        let combined = lines.joined(separator: "\n")
        return combined + "\n\nBu bir yatırım tavsiyesi değildir."
    }

    // MARK: - Build IndicatorSnapshot from candles
    func buildSnapshot(symbol: String, candles: [Candle]) -> IndicatorSnapshot {
        let closes  = candles.map { $0.close }
        let volumes = candles.map { $0.volume }

        let unusualMove = UnusualMoveDetector.detect(closes: closes)
        let macdResult  = MACDCalculator.latest(closes: closes)
        let bollinger   = BollingerBandsCalculator.latest(closes: closes)

        return IndicatorSnapshot(
            symbol: symbol,
            rsi14: RSICalculator.latest(closes: closes),
            sma20: SMACalculator.latest(closes: closes, period: 20),
            sma50: SMACalculator.latest(closes: closes, period: 50),
            volatilityScore: VolatilityCalculator.score(closes: closes),
            volumeAnomalyPct: VolumeAnomalyCalculator.anomalyPercent(volumes: volumes),
            change7d: PerformanceCalculator.change(closes: closes, days: 7),
            change30d: PerformanceCalculator.change(closes: closes, days: 30),
            isUnusualMove: unusualMove?.isUnusual ?? false,
            unusualMoveSigma: unusualMove?.sigma,
            ema20: EMACalculator.latest(closes: closes, period: 20),
            ema50: EMACalculator.latest(closes: closes, period: 50),
            macd: macdResult?.macd,
            macdSignal: macdResult?.signal,
            macdHistogram: macdResult?.histogram,
            bollingerUpper: bollinger?.upper,
            bollingerMiddle: bollinger?.middle,
            bollingerLower: bollinger?.lower,
            bollingerBandwidth: bollinger?.bandwidth,
            bollingerPercentB: bollinger?.percentB,
            stochRSI: StochasticRSICalculator.latest(closes: closes)
        )
    }

    // MARK: - Rule: Performance
    private func performanceInsights(snapshot: IndicatorSnapshot) -> [Insight] {
        var insights: [Insight] = []

        if let c7 = snapshot.change7d {
            let sign = c7 >= 0 ? "+" : ""
            let body = "Son 7 günde yaklaşık \(sign)\(String(format: "%.1f", c7))% değişim gerçekleşti."
            insights.append(Insight(
                category: .performance,
                severity: abs(c7) > 10 ? .warning : .neutral,
                title: "7 Günlük Performans",
                body: body,
                numericEvidence: "7g=\(sign)\(String(format: "%.1f", c7))%"
            ))
        }

        if let c30 = snapshot.change30d {
            let sign = c30 >= 0 ? "+" : ""
            let body = "Son 30 günde yaklaşık \(sign)\(String(format: "%.1f", c30))% değişim gerçekleşti."
            insights.append(Insight(
                category: .performance,
                severity: abs(c30) > 20 ? .warning : .neutral,
                title: "30 Günlük Performans",
                body: body,
                numericEvidence: "30g=\(sign)\(String(format: "%.1f", c30))%"
            ))
        }

        return insights
    }

    // MARK: - Rule: RSI
    private func rsiInsight(snapshot: IndicatorSnapshot) -> [Insight] {
        guard let rsi = snapshot.rsi14 else { return [] }
        let rsiStr = String(format: "%.1f", rsi)

        let (body, severity): (String, InsightSeverity)
        switch rsi {
        case ..<30:
            body = "RSI(14)=\(rsiStr): Aşırı satım bölgesinde. Teknik analizde bu bölge, fiyatın görece düşük seyrettiğine işaret eder; ancak bu otomatik bir alım sinyali değildir. (Eğitsel yorum)"
            severity = .warning
        case 30..<50:
            body = "RSI(14)=\(rsiStr): Nötr ile aşırı satım arası bölgede. Momentum göreceli zayıf seyrediyor. (Eğitsel yorum)"
            severity = .neutral
        case 50...70:
            body = "RSI(14)=\(rsiStr): Nötr ile aşırı alım arası bölgede. Momentum göreceli güçlü seyrediyor. (Eğitsel yorum)"
            severity = .neutral
        default:
            body = "RSI(14)=\(rsiStr): Aşırı alım bölgesine yakın. Teknik analizde bu bölge fiyatın görece yüksek seyrettiğine işaret eder; ancak bu otomatik bir satım sinyali değildir. (Eğitsel yorum)"
            severity = .warning
        }

        return [Insight(
            category: .momentum,
            severity: severity,
            title: "RSI Göstergesi",
            body: body,
            numericEvidence: "RSI(14)=\(rsiStr)"
        )]
    }

    // MARK: - Rule: Moving Averages
    private func movingAvgInsights(snapshot: IndicatorSnapshot, candles: [Candle]) -> [Insight] {
        guard let sma20 = snapshot.sma20, let sma50 = snapshot.sma50 else { return [] }
        let lastPrice = candles.last?.close ?? 0

        var insights: [Insight] = []

        let sma20Str = String(format: "%.2f", sma20)
        let sma50Str = String(format: "%.2f", sma50)
        let priceStr = String(format: "%.2f", lastPrice)

        // Price vs SMA20
        let aboveSMA20 = lastPrice > sma20
        let pctDiff20 = sma20 > 0 ? ((lastPrice - sma20) / sma20 * 100) : 0
        let dir20 = aboveSMA20 ? "üzerinde" : "altında"
        let pct20Str = String(format: "%.1f", abs(pctDiff20))
        insights.append(Insight(
            category: .movingAvg,
            title: "MA20 Konumu",
            body: "Fiyat (\(priceStr) ₺), 20 günlük hareketli ortalamanın (\(sma20Str) ₺) %\(pct20Str) \(dir20). Hareketli ortalama fiyatın trend yönünü anlamaya yardımcı olan eğitsel bir araçtır. (Eğitsel yorum)",
            numericEvidence: "Fiyat=\(priceStr), MA20=\(sma20Str)"
        ))

        // Price vs SMA50
        let aboveSMA50 = lastPrice > sma50
        let pctDiff50 = sma50 > 0 ? ((lastPrice - sma50) / sma50 * 100) : 0
        let dir50 = aboveSMA50 ? "üzerinde" : "altında"
        let pct50Str = String(format: "%.1f", abs(pctDiff50))
        insights.append(Insight(
            category: .movingAvg,
            title: "MA50 Konumu",
            body: "Fiyat, 50 günlük hareketli ortalamanın (\(sma50Str) ₺) %\(pct50Str) \(dir50). (Eğitsel yorum)",
            numericEvidence: "MA50=\(sma50Str)"
        ))

        // EMA values
        if let ema20 = snapshot.ema20, let ema50 = snapshot.ema50 {
            let ema20Str = String(format: "%.2f", ema20)
            let ema50Str = String(format: "%.2f", ema50)
            let aboveEMA20 = lastPrice > ema20
            let dirE20 = aboveEMA20 ? "üzerinde" : "altında"
            insights.append(Insight(
                category: .movingAvg,
                title: "EMA Konumu",
                body: "Fiyat, üstel hareketli ortalamaların (EMA20=\(ema20Str) ₺, EMA50=\(ema50Str) ₺) \(dirE20). EMA, son fiyatlara daha fazla ağırlık veren bir ortalama türüdür. (Eğitsel yorum)",
                numericEvidence: "EMA20=\(ema20Str), EMA50=\(ema50Str)"
            ))
        }

        // Crossover detection
        let closes = candles.map { $0.close }
        let sma20arr = SMACalculator.compute(closes: closes, period: 20)
        let sma50arr = SMACalculator.compute(closes: closes, period: 50)
        let crossover = CrossoverDetector.detect(sma20: sma20arr, sma50: sma50arr)

        switch crossover {
        case .goldenCross:
            insights.append(Insight(
                category: .movingAvg,
                severity: .info,
                title: "Altın Çapraz (Golden Cross)",
                body: "Kısa vadeli ortalama (MA20=\(sma20Str)), uzun vadeli ortalamayı (MA50=\(sma50Str)) yukarıdan kesmesi gözlemlendi. Bu teknik analizde 'altın çapraz' olarak bilinir ve eğitsel açıdan trendin değişimine işaret edebilir. Kesin bir sinyal değildir. (Eğitsel yorum)",
                numericEvidence: "MA20=\(sma20Str) > MA50=\(sma50Str)"
            ))
        case .deathCross:
            insights.append(Insight(
                category: .movingAvg,
                severity: .warning,
                title: "Ölüm Çaprazı (Death Cross)",
                body: "Kısa vadeli ortalama (MA20=\(sma20Str)), uzun vadeli ortalamayı (MA50=\(sma50Str)) aşağıdan kesmesi gözlemlendi. Bu teknik analizde 'ölüm çaprazı' olarak bilinir ve eğitsel açıdan zayıflayan momentum'a işaret edebilir. Kesin bir sinyal değildir. (Eğitsel yorum)",
                numericEvidence: "MA20=\(sma20Str) < MA50=\(sma50Str)"
            ))
        case .none:
            break
        }

        return insights
    }

    // MARK: - Rule: MACD
    private func macdInsight(snapshot: IndicatorSnapshot) -> [Insight] {
        guard let macd = snapshot.macd,
              let signal = snapshot.macdSignal,
              let histogram = snapshot.macdHistogram else { return [] }

        let macdStr  = String(format: "%.4f", macd)
        let sigStr   = String(format: "%.4f", signal)
        let histStr  = String(format: "%.4f", histogram)

        let crossDesc: String
        let severity: InsightSeverity
        if macd > signal && histogram > 0 {
            crossDesc = "MACD sinyal çizgisinin üzerinde ve histogram pozitif; yükselen momentum sinyali."
            severity = .info
        } else if macd < signal && histogram < 0 {
            crossDesc = "MACD sinyal çizgisinin altında ve histogram negatif; düşen momentum sinyali."
            severity = .warning
        } else {
            crossDesc = "MACD ve sinyal çizgisi yakın seyriyor."
            severity = .neutral
        }

        let aboveZero = macd > 0 ? "sıfır çizgisinin üzerinde (genel yükseliş eğilimi)" : "sıfır çizgisinin altında (genel düşüş eğilimi)"

        let body = "MACD=\(macdStr), Sinyal=\(sigStr), Histogram=\(histStr). MACD \(aboveZero). \(crossDesc) MACD, iki üstel ortalamanın farkını gösterir; sinyal geçişleri momentum değişimine işaret edebilir. (Eğitsel yorum)"

        return [Insight(
            category: .momentum,
            severity: severity,
            title: "MACD Göstergesi",
            body: body,
            numericEvidence: "MACD=\(macdStr), Sinyal=\(sigStr), Hist=\(histStr)"
        )]
    }

    // MARK: - Rule: Bollinger Bands
    private func bollingerInsight(snapshot: IndicatorSnapshot) -> [Insight] {
        guard let upper  = snapshot.bollingerUpper,
              let middle = snapshot.bollingerMiddle,
              let lower  = snapshot.bollingerLower,
              let bw     = snapshot.bollingerBandwidth,
              let pctB   = snapshot.bollingerPercentB else { return [] }

        let upperStr  = String(format: "%.2f", upper)
        let middleStr = String(format: "%.2f", middle)
        let lowerStr  = String(format: "%.2f", lower)
        let bwStr     = String(format: "%.1f", bw)
        let pctBStr   = String(format: "%.0f", pctB)

        let positionDesc: String
        let severity: InsightSeverity
        if pctB > 100 {
            positionDesc = "Fiyat üst bandın üzerinde; aşırı alım bölgesine yakın olabilir."
            severity = .warning
        } else if pctB > 80 {
            positionDesc = "Fiyat üst banda yakın (%B=\(pctBStr)); görece yüksek bölgede."
            severity = .info
        } else if pctB < 0 {
            positionDesc = "Fiyat alt bandın altında; aşırı satım bölgesine yakın olabilir."
            severity = .warning
        } else if pctB < 20 {
            positionDesc = "Fiyat alt banda yakın (%B=\(pctBStr)); görece düşük bölgede."
            severity = .info
        } else {
            positionDesc = "Fiyat bantlar arasında (%B=\(pctBStr)); orta bölgede."
            severity = .neutral
        }

        let squeezeNote = bw < 10 ? " Bant genişliği dar (\(bwStr)%); sıkışma (squeeze) dönemine işaret edebilir." : ""

        let body = "Bollinger Bantları — Üst=\(upperStr) ₺, Orta=\(middleStr) ₺, Alt=\(lowerStr) ₺. \(positionDesc)\(squeezeNote) Bollinger Bantları, fiyat volatilitesini görselleştiren eğitsel bir araçtır. (Eğitsel yorum)"

        return [Insight(
            category: .volatility,
            severity: severity,
            title: "Bollinger Bantları",
            body: body,
            numericEvidence: "BB_Üst=\(upperStr), BB_Orta=\(middleStr), BB_Alt=\(lowerStr), BW=\(bwStr)%"
        )]
    }

    // MARK: - Rule: Volume
    private func volumeInsight(snapshot: IndicatorSnapshot) -> [Insight] {
        guard let pct = snapshot.volumeAnomalyPct else { return [] }
        let pctStr = String(format: "%.0f", pct)

        let (body, severity): (String, InsightSeverity)
        if pct >= 200 {
            body = "Hacim, 20 günlük ortalamanın %\(pctStr)'i seviyesinde: belirgin bir artış söz konusu. Yüksek hacim, yatırımcı ilgisinin yoğunlaştığına işaret edebilir. (Eğitsel yorum)"
            severity = .warning
        } else if pct >= 150 {
            body = "Hacim, 20 günlük ortalamanın %\(pctStr)'i seviyesinde: ortalamanın belirgin üzerinde. (Eğitsel yorum)"
            severity = .info
        } else if pct < 50 {
            body = "Hacim, 20 günlük ortalamanın %\(pctStr)'i seviyesinde: görece düşük işlem hacmi. (Eğitsel yorum)"
            severity = .neutral
        } else {
            body = "Hacim, 20 günlük ortalamanın %\(pctStr)'i seviyesinde: normal aralıkta. (Eğitsel yorum)"
            severity = .neutral
        }

        return [Insight(
            category: .volume,
            severity: severity,
            title: "Hacim Analizi",
            body: body,
            numericEvidence: "Hacim=%\(pctStr) (20g ort.)"
        )]
    }

    // MARK: - Rule: Volatility
    private func volatilityInsight(snapshot: IndicatorSnapshot) -> [Insight] {
        guard let vol = snapshot.volatilityScore else { return [] }
        let volStr = String(format: "%.0f", vol)

        let (label, body): (String, String)
        switch vol {
        case ..<25:
            label = "Düşük"
            body = "Volatilite skoru \(volStr)/100 (\(label)): Fiyat hareketleri görece sakin seyrediyor. (Eğitsel yorum)"
        case 25..<50:
            label = "Orta"
            body = "Volatilite skoru \(volStr)/100 (\(label)): Ortalama fiyat dalgalanması gözlemleniyor. (Eğitsel yorum)"
        case 50..<75:
            label = "Yüksek"
            body = "Volatilite skoru \(volStr)/100 (\(label)): Fiyat dalgalanmaları artmış görünüyor. (Eğitsel yorum)"
        default:
            label = "Çok Yüksek"
            body = "Volatilite skoru \(volStr)/100 (\(label)): Fiyat hareketleri oldukça yoğun. Volatilite, hem yukarı hem aşağı yönlü hareketleri kapsar. (Eğitsel yorum)"
        }

        return [Insight(
            category: .volatility,
            severity: vol >= 75 ? .warning : .neutral,
            title: "Volatilite Skoru",
            body: body,
            numericEvidence: "Volatilite=\(volStr)/100"
        )]
    }

    // MARK: - Rule: Unusual Move
    private func unusualMoveInsight(snapshot: IndicatorSnapshot) -> [Insight] {
        guard snapshot.isUnusualMove, let sigma = snapshot.unusualMoveSigma else { return [] }
        let sigmaStr = String(format: "%.1f", sigma)

        let body = "Günlük fiyat hareketi, son 20 günlük standart sapmanın \(sigmaStr)σ katı kadar olağandışı. Bu istatistiksel açıdan nadir görülen bir harekete işaret eder; ancak nedeni piyasa haberleri, sektör gelişmeleri veya teknik faktörler olabilir. (Eğitsel yorum)"

        return [Insight(
            category: .unusual,
            severity: .warning,
            title: "Olağandışı Fiyat Hareketi",
            body: body,
            numericEvidence: "Hareket=\(sigmaStr)σ"
        )]
    }
}
