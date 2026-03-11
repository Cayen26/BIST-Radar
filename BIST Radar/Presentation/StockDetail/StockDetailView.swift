// StockDetailView.swift – Stock detail: chart + metrics + insights + assistant
// BIST Radar AI

import SwiftUI
import SwiftData
import Combine

struct StockDetailView: View {
    let company: Company

    @EnvironmentObject var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @State private var vm: StockDetailViewModel?
    @State private var showAssistant = false

    var body: some View {
        ZStack {
            Color.surface1.ignoresSafeArea()

            if let vm {
                ScrollView {
                    VStack(spacing: 24) {
                        // Price Header
                        priceHeader(vm: vm)

                        // Chart
                        PriceChartView(
                            candles: vm.candles,
                            isPositive: vm.quote?.isPositive ?? true,
                            selectedTimeframe: vm.selectedTimeframe,
                            onTimeframeChange: { tf in
                                Task { await vm.changeTimeframe(to: tf, symbol: company.symbol) }
                            }
                        )
                        .padding(.horizontal, 16)

                        // Key Metrics
                        metricsGrid(vm: vm)
                            .padding(.horizontal, 16)

                        // Fundamentals
                        if let funda = vm.fundamentals {
                            fundamentalsSection(funda: funda)
                                .padding(.horizontal, 16)
                        }

                        // Indicator Snapshot
                        if let snap = vm.snapshot {
                            indicatorSnapshot(snap)
                                .padding(.horizontal, 16)
                        }

                        // Insights
                        InsightsSectionView(insights: vm.insights, isLoading: vm.isLoading)
                            .padding(.horizontal, 16)

                        // Ask Assistant CTA
                        askAssistantButton()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                    }
                }
                .refreshable { await vm.load(symbol: company.symbol) }
            } else {
                ProgressView("Yükleniyor...")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .navigationTitle(company.symbol)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.surface1, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let isWL = appContainer.watchlistRepository.contains(
                    symbol: company.symbol, modelContext: modelContext
                )
                Button {
                    appContainer.watchlistRepository.toggle(
                        symbol: company.symbol,
                        companyNameTr: company.companyNameTr,
                        modelContext: modelContext
                    )
                } label: {
                    Image(systemName: isWL ? "star.fill" : "star")
                        .foregroundStyle(isWL ? Color.brandAccent : Color.textSecondary)
                }
            }
        }
        .sheet(isPresented: $showAssistant) {
            AssistantChatView(contextSymbol: company.symbol)
        }
        .onAppear {
            if vm == nil {
                vm = StockDetailViewModel(
                    quoteRepo: appContainer.quoteRepository,
                    insightEngine: appContainer.ruleInsightEngine
                )
            }
        }
        .task { await vm?.load(symbol: company.symbol) }
    }

    // MARK: - Price Header
    @ViewBuilder
    private func priceHeader(vm: StockDetailViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Company name + sector badge
            HStack(spacing: 8) {
                Text(company.companyNameTr)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(company.sector)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.sectorColor(for: company.sector))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.sectorColor(for: company.sector).opacity(0.14))
                    .clipShape(Capsule())
            }

            // Price row
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let q = vm.quote {
                    Text(q.formattedPrice)
                        .font(.system(size: 38, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                    ChangeBadge(value: q.changePercent)
                    if q.isDelayed {
                        Text("GECİKMELİ")
                            .font(.caption2.bold())
                            .foregroundStyle(Color.negative.opacity(0.8))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.negative.opacity(0.12))
                            .clipShape(Capsule())
                    }
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.surface3)
                        .frame(width: 160, height: 42)
                        .skeleton()
                }
            }

            // OHLV row
            if let q = vm.quote {
                HStack(spacing: 0) {
                    OHLVItem(label: "AÇILIŞ", value: String(format: "%.2f", q.open))
                    Divider().frame(height: 28).background(Color.surface3)
                    OHLVItem(label: "YÜKSEK", value: String(format: "%.2f", q.high))
                    Divider().frame(height: 28).background(Color.surface3)
                    OHLVItem(label: "DÜŞÜK", value: String(format: "%.2f", q.low))
                    Divider().frame(height: 28).background(Color.surface3)
                    OHLVItem(label: "HACİM", value: q.formattedVolume)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.surface3, lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Metrics Grid
    @ViewBuilder
    private func metricsGrid(vm: StockDetailViewModel) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Teknik Göstergeler", icon: "waveform.path")
            if let snap = vm.snapshot {
                LazyVGrid(columns: cols, spacing: 10) {
                    MetricCard(label: "RSI(14)",
                               value: snap.rsi14.map { String(format: "%.1f", $0) } ?? "—",
                               subtitle: rsiLabel(snap.rsi14),
                               valueColor: rsiColor(snap.rsi14),
                               icon: "gauge.medium")
                    MetricCard(label: "MA20",
                               value: snap.sma20.map { String(format: "%.2f", $0) } ?? "—",
                               subtitle: "Ort. 20g",
                               icon: "chart.line.uptrend.xyaxis")
                    MetricCard(label: "MA50",
                               value: snap.sma50.map { String(format: "%.2f", $0) } ?? "—",
                               subtitle: "Ort. 50g",
                               icon: "chart.line.flattrend.xyaxis")
                    MetricCard(label: "Volatilite",
                               value: snap.volatilityScore.map { String(format: "%.0f", $0) } ?? "—",
                               subtitle: "/100",
                               icon: "bolt.fill")
                    MetricCard(label: "Hacim",
                               value: snap.volumeAnomalyPct.map { String(format: "%.0f%%", $0) } ?? "—",
                               subtitle: "20g ortalama",
                               icon: "waveform.path.ecg")
                    MetricCard(label: "7g Değ.",
                               value: snap.change7d.map { String.percentFormatted($0, digits: 1) } ?? "—",
                               subtitle: "7 gün",
                               valueColor: changeColor(snap.change7d),
                               icon: "calendar.badge.clock")
                }
            } else if vm.isLoading {
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(0..<6, id: \.self) { _ in CardSkeleton(height: 76) }
                }
            }
        }
    }

    // MARK: - Fundamentals Section
    @ViewBuilder
    private func fundamentalsSection(funda: Fundamentals) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Finansallar", icon: "building.columns")
            LazyVGrid(columns: cols, spacing: 10) {
                MetricCard(label: "F/K", value: funda.formattedPE, subtitle: "Fiyat/Kazanç", icon: "dollarsign.circle")
                MetricCard(label: "PD/DD", value: funda.formattedPB, subtitle: "Piyasa/Defter", icon: "building.2")
                MetricCard(label: "Temettü", value: funda.formattedDividend, subtitle: "Verimi", icon: "gift")
                MetricCard(label: "Piy. Değ.", value: funda.formattedMarketCap, subtitle: "TL", icon: "chart.pie")
                if let ff = funda.freefloatPct {
                    MetricCard(label: "Halka Açık",
                               value: String(format: "%%%.0f", ff), subtitle: "", icon: "person.2")
                }
                if let roe = funda.roe {
                    MetricCard(label: "Özkaynak Kârl.", value: String(format: "%%%.1f", roe), subtitle: "ROE", icon: "percent")
                }
            }
            if funda.isDelayed {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("Finansal veriler gecikmeli olabilir.")
                        .font(.caption2)
                }
                .foregroundStyle(Color.textTertiary)
            }
        }
    }

    // MARK: - Indicator Snapshot mini display
    @ViewBuilder
    private func indicatorSnapshot(_ snap: IndicatorSnapshot) -> some View {
        if snap.isUnusualMove, let sigma = snap.unusualMoveSigma {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(hex: "#F59E0B").opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color(hex: "#F59E0B"))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Olağandışı Hareket")
                        .font(.caption.bold())
                        .foregroundStyle(Color.textPrimary)
                    Text("\(String(format: "%.1f", sigma))σ standart sapma")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
            }
            .padding(12)
            .background(Color(hex: "#F59E0B").opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(hex: "#F59E0B").opacity(0.3), lineWidth: 1)
            )
        }
    }

    // MARK: - Ask Assistant button
    @ViewBuilder
    private func askAssistantButton() -> some View {
        Button {
            showAssistant = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Asistana Sor")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(company.symbol)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                LinearGradient(
                    colors: [Color.brandAccent, Color(hex: "#0082AA")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color.brandAccent.opacity(0.35), radius: 14, x: 0, y: 5)
        }
    }

    // MARK: - Helpers
    private func rsiLabel(_ rsi: Double?) -> String {
        guard let rsi else { return "" }
        switch rsi {
        case ..<30: return "Aşırı satım"
        case 70...: return "Aşırı alım"
        default:    return "Nötr"
        }
    }

    private func rsiColor(_ rsi: Double?) -> Color {
        guard let rsi else { return .textPrimary }
        switch rsi {
        case ..<30: return .positive
        case 70...: return .negative
        default:    return .textPrimary
        }
    }

    private func changeColor(_ change: Double?) -> Color {
        guard let c = change else { return .textSecondary }
        return c >= 0 ? .positive : .negative
    }
}

// MARK: - OHLV Item
struct OHLVItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Metric Card
struct MetricCard: View {
    let label: String
    let value: String
    let subtitle: String
    var valueColor: Color = .textPrimary
    var icon: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Color.brandAccent.opacity(0.8))
                }
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
            Text(value)
                .font(.callout.monospaced().weight(.bold))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.surface3, lineWidth: 1)
        )
    }
}

// MARK: - Metric Label (inline)
struct MetricLabel: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.caption.monospaced())
                .foregroundStyle(Color.textPrimary)
        }
    }
}

