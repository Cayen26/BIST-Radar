// TechnicalIndicators.swift – Pure, testable indicator functions
// BIST Radar AI

import Foundation

// MARK: - RSI (Wilder's smoothed method, period=14)
enum RSICalculator {
    /// Returns RSI values array aligned with input closes (nil for warmup period).
    static func compute(closes: [Double], period: Int = 14) -> [Double?] {
        guard closes.count > period else { return Array(repeating: nil, count: closes.count) }
        var results: [Double?] = Array(repeating: nil, count: closes.count)
        var gains: [Double] = []
        var losses: [Double] = []

        for i in 1..<closes.count {
            let diff = closes[i] - closes[i - 1]
            gains.append(max(diff, 0))
            losses.append(max(-diff, 0))
        }

        // Initial averages (simple mean)
        var avgGain = gains.prefix(period).reduce(0, +) / Double(period)
        var avgLoss = losses.prefix(period).reduce(0, +) / Double(period)

        func rsi(ag: Double, al: Double) -> Double {
            al == 0 ? 100 : 100 - (100 / (1 + ag / al))
        }

        results[period] = rsi(ag: avgGain, al: avgLoss)

        // Wilder smoothing
        for i in (period + 1)..<closes.count {
            let idx = i - 1  // gains/losses are 1-offset
            avgGain = (avgGain * Double(period - 1) + gains[idx]) / Double(period)
            avgLoss = (avgLoss * Double(period - 1) + losses[idx]) / Double(period)
            results[i] = rsi(ag: avgGain, al: avgLoss)
        }
        return results
    }

    static func latest(closes: [Double], period: Int = 14) -> Double? {
        compute(closes: closes, period: period).last ?? nil
    }
}

// MARK: - SMA (Simple Moving Average)
enum SMACalculator {
    static func compute(closes: [Double], period: Int) -> [Double?] {
        guard closes.count >= period else { return Array(repeating: nil, count: closes.count) }
        var results: [Double?] = Array(repeating: nil, count: closes.count)
        for i in (period - 1)..<closes.count {
            let slice = closes[(i - period + 1)...i]
            results[i] = slice.reduce(0, +) / Double(period)
        }
        return results
    }

    static func latest(closes: [Double], period: Int) -> Double? {
        guard closes.count >= period else { return nil }
        let slice = closes.suffix(period)
        return slice.reduce(0, +) / Double(period)
    }
}

// MARK: - Volatility Score (0–100)
// Uses annualized standard deviation of daily log-returns, mapped to 0–100.
enum VolatilityCalculator {
    /// Returns score in 0–100 range. Typical stocks: 20–60.
    static func score(closes: [Double], window: Int = 20) -> Double? {
        guard closes.count >= window + 1 else { return nil }
        let recent = closes.suffix(window + 1)
        let prices = Array(recent)

        var logReturns: [Double] = []
        for i in 1..<prices.count {
            guard prices[i - 1] > 0 else { continue }
            logReturns.append(log(prices[i] / prices[i - 1]))
        }
        guard logReturns.count > 1 else { return nil }

        let mean = logReturns.reduce(0, +) / Double(logReturns.count)
        let variance = logReturns.map { pow($0 - mean, 2) }.reduce(0, +) / Double(logReturns.count - 1)
        let stdDev = sqrt(variance)
        let annualized = stdDev * sqrt(252) * 100  // as percent

        // Map: 0%=0, 100%=100 (cap at 100)
        return min(annualized, 100)
    }
}

// MARK: - Volume Anomaly (% vs N-day average)
enum VolumeAnomalyCalculator {
    /// Returns volume as % of average. 100 = average. 250 = 2.5x average.
    static func anomalyPercent(volumes: [Double], window: Int = 20) -> Double? {
        guard volumes.count >= window + 1 else { return nil }
        let historicalSlice = volumes.dropLast().suffix(window)
        let avgVol = historicalSlice.reduce(0, +) / Double(historicalSlice.count)
        guard avgVol > 0 else { return nil }
        let todayVol = volumes.last!
        return (todayVol / avgVol) * 100
    }
}

// MARK: - Unusual Move Detection (>N sigma)
enum UnusualMoveDetector {
    struct UnusualMoveResult: Sendable {
        let isUnusual: Bool
        let sigma: Double
        let todayReturn: Double
    }

    static func detect(closes: [Double], sigmaThreshold: Double = 2.0, window: Int = 20) -> UnusualMoveResult? {
        guard closes.count >= window + 1 else { return nil }
        let recent = Array(closes.suffix(window + 1))

        var returns: [Double] = []
        for i in 1..<recent.count {
            guard recent[i - 1] > 0 else { continue }
            returns.append((recent[i] - recent[i - 1]) / recent[i - 1])
        }
        guard returns.count > 1 else { return nil }

        let historicalReturns = returns.dropLast()
        let todayReturn = returns.last!
        let mean = historicalReturns.reduce(0, +) / Double(historicalReturns.count)
        let variance = historicalReturns.map { pow($0 - mean, 2) }.reduce(0, +) / Double(historicalReturns.count)
        let std = sqrt(variance)
        guard std > 0 else { return nil }

        let sigma = abs(todayReturn - mean) / std
        return UnusualMoveResult(
            isUnusual: sigma >= sigmaThreshold,
            sigma: sigma,
            todayReturn: todayReturn * 100
        )
    }
}

// MARK: - Performance helpers
enum PerformanceCalculator {
    static func change(closes: [Double], days: Int) -> Double? {
        guard closes.count >= days + 1 else { return nil }
        let base = closes[closes.count - 1 - days]
        let last = closes.last!
        guard base != 0 else { return nil }
        return ((last - base) / base) * 100
    }
}

// MARK: - Support / Resistance levels
enum SupportResistanceCalculator {

    struct Level: Sendable {
        let price: Double
        let strength: Int   // how many times this area was tested
        let isSupport: Bool
    }

    struct Result: Sendable {
        let supports: [Double]    // ascending, below current price
        let resistances: [Double] // ascending, above current price
        let pivotPoint: Double
        let r1: Double
        let r2: Double
        let s1: Double
        let s2: Double
    }

    /// Compute pivot points from the most recent candle's H/L/C
    static func pivots(candles: [Candle]) -> (pp: Double, r1: Double, r2: Double, s1: Double, s2: Double)? {
        guard let last = candles.last else { return nil }
        let pp = (last.high + last.low + last.close) / 3
        let r1 = 2 * pp - last.low
        let r2 = pp + (last.high - last.low)
        let s1 = 2 * pp - last.high
        let s2 = pp - (last.high - last.low)
        return (pp, r1, r2, s1, s2)
    }

    /// Detect swing highs/lows and cluster into support/resistance zones
    static func compute(candles: [Candle], tolerance: Double = 0.015) -> Result? {
        guard candles.count >= 20, let last = candles.last else { return nil }
        let current = last.close

        // Find swing highs (local maxima) and swing lows (local minima)
        let window = 3
        var swingHighs: [Double] = []
        var swingLows: [Double] = []

        for i in window..<(candles.count - window) {
            let c = candles[i]
            let highs = (i - window..<i).map { candles[$0].high }
            let lows  = (i - window..<i).map { candles[$0].low }
            let futureHighs = ((i + 1)..<(i + window + 1)).map { candles[$0].high }
            let futureLows  = ((i + 1)..<(i + window + 1)).map { candles[$0].low }

            let isSwingHigh = c.high > (highs.max() ?? 0) && c.high > (futureHighs.max() ?? 0)
            let isSwingLow  = c.low  < (lows.min()  ?? 0) && c.low  < (futureLows.min()  ?? 0)

            if isSwingHigh { swingHighs.append(c.high) }
            if isSwingLow  { swingLows.append(c.low) }
        }

        // Cluster nearby levels within tolerance %
        func cluster(_ prices: [Double]) -> [Double] {
            var sorted = prices.sorted()
            var clusters: [Double] = []
            var i = 0
            while i < sorted.count {
                let base = sorted[i]
                var group = [base]
                var j = i + 1
                while j < sorted.count, abs(sorted[j] - base) / base < tolerance {
                    group.append(sorted[j])
                    j += 1
                }
                clusters.append(group.reduce(0, +) / Double(group.count))
                i = j
            }
            return clusters
        }

        let clusteredHighs = cluster(swingHighs)
        let clusteredLows  = cluster(swingLows)

        // Split by current price
        let supports    = clusteredLows.filter  { $0 < current }.sorted()
        let resistances = clusteredHighs.filter { $0 > current }.sorted()

        guard let pivs = pivots(candles: candles) else { return nil }

        return Result(
            supports:    Array(supports.suffix(3)),
            resistances: Array(resistances.prefix(3)),
            pivotPoint: pivs.pp,
            r1: pivs.r1, r2: pivs.r2,
            s1: pivs.s1, s2: pivs.s2
        )
    }
}

// MARK: - EMA (Exponential Moving Average)
enum EMACalculator {
    /// Returns EMA values array aligned with input closes (nil for warmup period).
    static func compute(closes: [Double], period: Int) -> [Double?] {
        guard closes.count >= period else { return Array(repeating: nil, count: closes.count) }
        var results: [Double?] = Array(repeating: nil, count: closes.count)
        let multiplier = 2.0 / Double(period + 1)

        // Seed with SMA of first `period` values
        let seedSMA = closes.prefix(period).reduce(0, +) / Double(period)
        results[period - 1] = seedSMA
        var prev = seedSMA

        for i in period..<closes.count {
            let ema = (closes[i] - prev) * multiplier + prev
            results[i] = ema
            prev = ema
        }
        return results
    }

    static func latest(closes: [Double], period: Int) -> Double? {
        compute(closes: closes, period: period).last ?? nil
    }
}

// MARK: - MACD (12/26/9)
enum MACDCalculator {
    struct MACDResult: Sendable {
        let macd: Double      // EMA12 - EMA26
        let signal: Double    // 9-period EMA of MACD
        let histogram: Double // MACD - Signal
    }

    static func compute(closes: [Double]) -> [MACDResult?] {
        let ema12 = EMACalculator.compute(closes: closes, period: 12)
        let ema26 = EMACalculator.compute(closes: closes, period: 26)

        // Build MACD line (only where both EMAs exist)
        var macdLine: [Double?] = Array(repeating: nil, count: closes.count)
        for i in 0..<closes.count {
            if let e12 = ema12[i], let e26 = ema26[i] {
                macdLine[i] = e12 - e26
            }
        }

        // Build signal line (9-period EMA of MACD line)
        let macdValues = macdLine.compactMap { $0 }
        guard macdValues.count >= 9 else { return Array(repeating: nil, count: closes.count) }

        let signalEMA = EMACalculator.compute(closes: macdValues, period: 9)

        // Align signal with macdLine
        var results: [MACDResult?] = Array(repeating: nil, count: closes.count)
        let macdStartIdx = macdLine.firstIndex(where: { $0 != nil }) ?? 0
        var signalIdx = 0
        for i in macdStartIdx..<closes.count {
            guard let macdVal = macdLine[i] else { continue }
            if signalIdx < signalEMA.count, let sig = signalEMA[signalIdx] {
                results[i] = MACDResult(macd: macdVal, signal: sig, histogram: macdVal - sig)
            }
            signalIdx += 1
        }
        return results
    }

    static func latest(closes: [Double]) -> MACDResult? {
        compute(closes: closes).last ?? nil
    }
}

// MARK: - Bollinger Bands (20, ±2σ)
enum BollingerBandsCalculator {
    struct BollingerResult: Sendable {
        let upper: Double
        let middle: Double   // SMA20
        let lower: Double
        let bandwidth: Double   // (upper-lower)/middle * 100
        let percentB: Double    // (price-lower)/(upper-lower)*100
    }

    static func latest(closes: [Double], period: Int = 20, multiplier: Double = 2.0) -> BollingerResult? {
        guard closes.count >= period, let price = closes.last else { return nil }
        let slice = Array(closes.suffix(period))
        let middle = slice.reduce(0, +) / Double(period)
        let variance = slice.map { pow($0 - middle, 2) }.reduce(0, +) / Double(period)
        let stdDev = sqrt(variance)
        let upper = middle + multiplier * stdDev
        let lower = middle - multiplier * stdDev
        let bandwidth = middle > 0 ? (upper - lower) / middle * 100 : 0
        let range = upper - lower
        let percentB = range > 0 ? (price - lower) / range * 100 : 50
        return BollingerResult(upper: upper, middle: middle, lower: lower,
                               bandwidth: bandwidth, percentB: percentB)
    }
}

// MARK: - Stochastic RSI
enum StochasticRSICalculator {
    /// Returns StochRSI in 0–100 range (nil if insufficient data).
    static func latest(closes: [Double], rsiPeriod: Int = 14, stochPeriod: Int = 14) -> Double? {
        let rsiValues = RSICalculator.compute(closes: closes, period: rsiPeriod).compactMap { $0 }
        guard rsiValues.count >= stochPeriod else { return nil }
        let window = Array(rsiValues.suffix(stochPeriod))
        guard let minRSI = window.min(), let maxRSI = window.max() else { return nil }
        let range = maxRSI - minRSI
        guard range > 0 else { return 50 }
        let currentRSI = rsiValues.last!
        return (currentRSI - minRSI) / range * 100
    }
}

// MARK: - Crossover detection
enum CrossoverDetector {
    enum CrossoverType: Sendable {
        case goldenCross   // MA20 crosses above MA50 (bullish signal, educational)
        case deathCross    // MA20 crosses below MA50 (bearish signal, educational)
        case none
    }

    /// Detects if a crossover happened recently (within `lookback` bars).
    static func detect(sma20: [Double?], sma50: [Double?], lookback: Int = 3) -> CrossoverType {
        let count = min(sma20.count, sma50.count)
        guard count >= lookback + 1 else { return .none }

        let recent20 = Array(sma20.suffix(lookback + 1).compactMap { $0 })
        let recent50 = Array(sma50.suffix(lookback + 1).compactMap { $0 })
        guard recent20.count >= 2, recent50.count >= 2 else { return .none }

        let prevAbove = recent20[recent20.count - 2] > recent50[recent50.count - 2]
        let currAbove = recent20.last! > recent50.last!

        if !prevAbove && currAbove { return .goldenCross }
        if prevAbove && !currAbove { return .deathCross }
        return .none
    }
}
