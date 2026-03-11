// BISTRadarTests.swift – Unit tests for Analytics + Turkish normalization
// BIST Radar AI

import XCTest
@testable import BIST_Radar

final class BISTRadarTests: XCTestCase {

    // MARK: - Turkish normalization tests
    func testTurkishNormalization_basicMapping() {
        XCTAssertEqual("İstanbul".turkishNormalized(), "istanbul")
        XCTAssertEqual("Şişecam".turkishNormalized(), "sisecam")
        XCTAssertEqual("Gübre".turkishNormalized(), "gubre")
        XCTAssertEqual("Ülker".turkishNormalized(), "ulker")
        XCTAssertEqual("Öteyanda".turkishNormalized(), "oteyanda")
        XCTAssertEqual("Çimento".turkishNormalized(), "cimento")
    }

    func testTurkishNormalization_searchMatch() {
        let name = "Türk Hava Yolları A.O."
        XCTAssertTrue(name.turkishContains("turk"))
        XCTAssertTrue(name.turkishContains("hava"))
        XCTAssertTrue(name.turkishContains("yollari"))
        XCTAssertFalse(name.turkishContains("garanti"))
    }

    func testTurkishNormalization_symbol() {
        XCTAssertEqual("THYAO".turkishNormalized(), "thyao")
        XCTAssertEqual("İSBANK".turkishNormalized(), "isbank")
    }

    // MARK: - RSI tests
    func testRSI_constant_prices() {
        // Constant prices → no gains/losses → RSI should be nil or special
        let closes = Array(repeating: 100.0, count: 20)
        let rsi = RSICalculator.latest(closes: closes)
        // With no movement, avgLoss = 0 → RSI = 100
        if let rsi { XCTAssertEqual(rsi, 100.0, accuracy: 0.1) }
    }

    func testRSI_overbought_range() {
        // Strongly uptrending prices → RSI should be > 70
        var closes = [Double]()
        for i in 0..<25 { closes.append(100.0 + Double(i) * 2) }
        let rsi = RSICalculator.latest(closes: closes)
        XCTAssertNotNil(rsi)
        if let rsi { XCTAssertGreaterThan(rsi, 70.0) }
    }

    func testRSI_oversold_range() {
        // Strongly downtrending prices → RSI should be < 30
        var closes = [Double]()
        for i in 0..<25 { closes.append(200.0 - Double(i) * 3) }
        let rsi = RSICalculator.latest(closes: closes)
        XCTAssertNotNil(rsi)
        if let rsi { XCTAssertLessThan(rsi, 30.0) }
    }

    func testRSI_insufficient_data() {
        let closes = [100.0, 101.0, 102.0]
        let rsi = RSICalculator.latest(closes: closes)
        XCTAssertNil(rsi)
    }

    // MARK: - SMA tests
    func testSMA_simple() {
        let closes = [1.0, 2.0, 3.0, 4.0, 5.0]
        let sma = SMACalculator.latest(closes: closes, period: 5)
        XCTAssertEqual(sma!, 3.0, accuracy: 0.001)
    }

    func testSMA_period_5() {
        let closes = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0]
        let sma = SMACalculator.latest(closes: closes, period: 5)
        XCTAssertEqual(sma!, 40.0, accuracy: 0.001) // (20+30+40+50+60)/5
    }

    func testSMA_insufficient() {
        let closes = [10.0, 20.0]
        XCTAssertNil(SMACalculator.latest(closes: closes, period: 5))
    }

    // MARK: - Volatility tests
    func testVolatility_zero_movement() {
        let closes = Array(repeating: 100.0, count: 25)
        let score = VolatilityCalculator.score(closes: closes)
        XCTAssertNotNil(score)
        if let score { XCTAssertEqual(score, 0.0, accuracy: 0.001) }
    }

    func testVolatility_high_movement() {
        var closes = [Double]()
        for i in 0..<25 {
            closes.append(i % 2 == 0 ? 100.0 : 150.0)
        }
        let score = VolatilityCalculator.score(closes: closes)
        XCTAssertNotNil(score)
        if let score { XCTAssertGreaterThan(score, 50.0) }
    }

    // MARK: - Volume Anomaly tests
    func testVolumeAnomaly_normal() {
        // Last volume = average → 100%
        let vols = Array(repeating: 1_000_000.0, count: 21)
        let pct = VolumeAnomalyCalculator.anomalyPercent(volumes: vols)
        XCTAssertEqual(pct!, 100.0, accuracy: 0.01)
    }

    func testVolumeAnomaly_spike() {
        var vols = Array(repeating: 1_000_000.0, count: 20)
        vols.append(3_000_000.0)  // 3x normal
        let pct = VolumeAnomalyCalculator.anomalyPercent(volumes: vols)
        XCTAssertNotNil(pct)
        if let pct { XCTAssertEqual(pct, 300.0, accuracy: 1.0) }
    }

    // MARK: - Unusual move tests
    func testUnusualMove_detected() {
        var closes: [Double] = []
        for _ in 0..<20 { closes.append(100.0 + Double.random(in: -1...1)) }
        closes.append(200.0)  // Huge move
        let result = UnusualMoveDetector.detect(closes: closes)
        XCTAssertNotNil(result)
        if let r = result { XCTAssertTrue(r.isUnusual) }
    }

    func testUnusualMove_not_detected() {
        var closes: [Double] = []
        for i in 0..<22 { closes.append(100.0 + Double(i) * 0.1) }
        let result = UnusualMoveDetector.detect(closes: closes)
        // Small, consistent moves → not unusual
        if let r = result { XCTAssertFalse(r.isUnusual) }
    }

    // MARK: - SafetyFilter tests
    func testSafetyFilter_blocks_buy() {
        let filter = SafetyFilter()
        let issues = filter.validate("Bu hisseyi satın alın!")
        XCTAssertFalse(issues.isEmpty)
    }

    func testSafetyFilter_adds_disclaimer() {
        let filter = SafetyFilter()
        let output = filter.filter("RSI 68 seviyesinde.")
        XCTAssertTrue(output.contains("Bu bir yatırım tavsiyesi değildir."))
    }

    func testSafetyFilter_clean_text_passes() {
        let filter = SafetyFilter()
        let text = "RSI(14)=45.2: Nötr bölgede.\n\nBu bir yatırım tavsiyesi değildir."
        XCTAssertTrue(filter.validate(text).isEmpty)
    }

    // MARK: - Insight generation tests
    func testRuleInsightEngine_generates_insights() {
        let engine = RuleInsightEngine()
        let candles = makeSampleCandles(count: 60)
        let snapshot = engine.buildSnapshot(symbol: "THYAO", candles: candles)
        let insights = engine.generateInsights(snapshot: snapshot, candles: candles)
        XCTAssertFalse(insights.isEmpty)
    }

    func testRuleInsightEngine_full_text_has_disclaimer() {
        let engine = RuleInsightEngine()
        let candles = makeSampleCandles(count: 60)
        let snapshot = engine.buildSnapshot(symbol: "THYAO", candles: candles)
        let text = engine.fullInsightText(snapshot: snapshot, candles: candles)
        XCTAssertTrue(text.contains("Bu bir yatırım tavsiyesi değildir."))
    }

    // MARK: - Helpers
    private func makeSampleCandles(count: Int) -> [Candle] {
        var candles: [Candle] = []
        var price = 100.0
        for i in 0..<count {
            let open = price
            let change = Double.random(in: -3...4)
            let close = max(1, price + change)
            let high = max(open, close) + Double.random(in: 0...2)
            let low  = min(open, close) - Double.random(in: 0...2)
            candles.append(Candle(
                timestamp: Calendar.current.date(byAdding: .day, value: i, to: Date())!,
                open: open, high: high, low: low, close: close,
                volume: Double.random(in: 5e6...20e6)
            ))
            price = close
        }
        return candles
    }
}
