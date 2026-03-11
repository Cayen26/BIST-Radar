// PriceChartView.swift – Interactive line price chart using Swift Charts
// BIST Radar AI

import SwiftUI
import Charts

struct PriceChartView: View {
    let candles: [Candle]
    let isPositive: Bool
    let selectedTimeframe: CandleTimeframe
    var onTimeframeChange: ((CandleTimeframe) -> Void)? = nil

    // Sürükleme / dokunma seçimi
    @State private var selectedDate: Date? = nil

    private var chartColor: Color { isPositive ? .positive : .negative }

    private var displayCandles: [Candle] {
        Array(candles.suffix(selectedTimeframe.candleLimit))
    }

    // Seçili tarihe en yakın mumu bul
    private var selectedCandle: Candle? {
        guard let date = selectedDate else { return nil }
        return displayCandles.min(by: {
            abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date))
        })
    }

    private var priceRange: (min: Double, max: Double) {
        let prices = displayCandles.map { $0.close }
        let mn = prices.min() ?? 0
        let mx = prices.max() ?? 100
        let pad = (mx - mn) * 0.12
        return (mn - pad, mx + pad)
    }

    // 1G için gün başlangıcından değişim
    private func changeFromDayOpen(_ candle: Candle) -> Double {
        guard let first = displayCandles.first, first.open != 0 else { return candle.changePercent }
        return ((candle.close - first.open) / first.open) * 100
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Tooltip (dokunulduğunda görünür) ────────────────────────────
            ZStack {
                if let candle = selectedCandle {
                    tooltipView(candle: candle)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    // Yer tutucu – layout kaymasın
                    Color.clear
                }
            }
            .frame(height: 34)
            .animation(.easeInOut(duration: 0.08), value: selectedCandle?.timestamp)
            .padding(.bottom, 4)

            // ── Grafik ──────────────────────────────────────────────────────
            if candles.isEmpty {
                ChartSkeleton()
            } else {
                Chart(displayCandles) { candle in
                    // Alan dolgusu
                    AreaMark(
                        x: .value("Tarih", candle.timestamp),
                        yStart: .value("Alt", priceRange.min),
                        yEnd: .value("Fiyat", candle.close)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [chartColor.opacity(0.28), chartColor.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    // Fiyat çizgisi
                    LineMark(
                        x: .value("Tarih", candle.timestamp),
                        y: .value("Fiyat", candle.close)
                    )
                    .foregroundStyle(chartColor)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)

                    // ── Crosshair (seçili mumda) ─────────────────────────
                    if let sel = selectedCandle, sel.id == candle.id {
                        // Kesik dikey çizgi
                        RuleMark(x: .value("Seçili", candle.timestamp))
                            .foregroundStyle(Color.textTertiary.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))

                        // Nokta – beyaz dış halka
                        PointMark(
                            x: .value("Tarih", candle.timestamp),
                            y: .value("Fiyat", candle.close)
                        )
                        .foregroundStyle(Color.surface1)
                        .symbolSize(110)

                        // Nokta – renkli iç
                        PointMark(
                            x: .value("Tarih", candle.timestamp),
                            y: .value("Fiyat", candle.close)
                        )
                        .foregroundStyle(chartColor)
                        .symbolSize(50)
                    }
                }
                // iOS 17+ interaktif seçim – parmakla sürükle
                .chartXSelection(value: $selectedDate)
                .chartYScale(domain: priceRange.min...priceRange.max)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.surface3)
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(axisLabel(date))
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.surface3)
                        AxisValueLabel {
                            if let d = value.as(Double.self) {
                                Text(String(format: "%.2f", d))
                                    .font(.system(size: 9))
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                    }
                }
                .frame(height: 200)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // ── Timeframe seçici ────────────────────────────────────────────
            HStack(spacing: 0) {
                ForEach(CandleTimeframe.allCases, id: \.self) { tf in
                    Button(tf.displayName) {
                        selectedDate = nil        // seçimi temizle
                        onTimeframeChange?(tf)
                    }
                    .font(.caption.bold())
                    .foregroundStyle(tf == selectedTimeframe ? Color.brandAccent : Color.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        tf == selectedTimeframe
                            ? Color.brandAccent.opacity(0.15)
                            : Color.clear
                    )
                }
            }
            .background(Color.surface2)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 8)
        }
    }

    // MARK: - Tooltip

    private func tooltipView(candle: Candle) -> some View {
        HStack(spacing: 10) {
            Text(tooltipLabel(candle.timestamp))
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiary)

            Spacer()

            Text(String(format: "%.2f", candle.close))
                .font(.system(.subheadline, design: .monospaced, weight: .bold))
                .foregroundStyle(Color.textPrimary)

            // 1G'de günün başından değişim, diğerlerinde mum değişimi
            let pct = selectedTimeframe == .oneDay ? changeFromDayOpen(candle) : candle.changePercent
            let sign = pct >= 0 ? "+" : ""
            Text("\(sign)\(String(format: "%.2f", pct))%")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(pct >= 0 ? Color.positive : Color.negative)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background((pct >= 0 ? Color.positive : Color.negative).opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(Color.surface3)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Date Formatting

    private func axisLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = selectedTimeframe == .oneDay ? "HH:mm" : "d MMM"
        return fmt.string(from: date)
    }

    private func tooltipLabel(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "tr_TR")
        fmt.dateFormat = selectedTimeframe == .oneDay ? "HH:mm" : "d MMM yyyy"
        return fmt.string(from: date)
    }
}

// MARK: - Mini sparkline (for watchlist rows)
struct SparklineView: View {
    let values: [Double]
    let isPositive: Bool
    var width: CGFloat = 60
    var height: CGFloat = 28

    var body: some View {
        if values.count < 2 {
            Color.surface3.frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Chart(Array(values.enumerated()), id: \.offset) { idx, val in
                LineMark(
                    x: .value("i", idx),
                    y: .value("v", val)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(isPositive ? Color.positive : Color.negative)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: width, height: height)
        }
    }
}
