// DashboardView.swift – Market Overview Dashboard
// BIST Radar AI

import SwiftUI
import SwiftData

struct DashboardView: View {
    @EnvironmentObject var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Company.symbol) private var companies: [Company]

    @State private var vm: DashboardViewModel?
    @State private var selectedStock: Company?
    @State private var selectedSector: Sector?
    @State private var showAssistant = false

    private var allSymbols: [String] {
        companies.filter { $0.isActive }.map { $0.symbol }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface1.ignoresSafeArea()

                if let vm {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Hata banner'ı
                            if let errMsg = vm.error {
                                HStack(spacing: 10) {
                                    Image(systemName: "wifi.exclamationmark")
                                        .foregroundStyle(Color.negative)
                                    Text(errMsg)
                                        .font(.caption)
                                        .foregroundStyle(Color.textSecondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.negative.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .padding(.horizontal, 16)
                            }

                            // BIST Index Cards
                            BISTIndexSection(vm: vm)

                            // Sector Strip
                            SectorStripSection(vm: vm, onSectorTap: { selectedSector = $0 })

                            // Top Movers (Horizontal scroll cards)
                            TopMoversSection(
                                title: "En Çok Yükselen",
                                icon: "arrow.up.right.circle.fill",
                                iconColor: .positive,
                                quotes: vm.topGainers,
                                companies: companies,
                                onTap: { selectedStock = $0 }
                            )

                            TopMoversSection(
                                title: "En Çok Düşen",
                                icon: "arrow.down.right.circle.fill",
                                iconColor: .negative,
                                quotes: vm.topLosers,
                                companies: companies,
                                onTap: { selectedStock = $0 }
                            )

                            // Volume section (list style)
                            VolumeSection(
                                quotes: vm.volumeSpikes,
                                companies: companies,
                                onTap: { selectedStock = $0 }
                            )

                            Spacer(minLength: 24)
                        }
                        .padding(.top, 12)
                    }
                    .refreshable { await vm.load(allSymbols: allSymbols) }
                } else {
                    ProgressView("Yükleniyor...")
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .navigationTitle("Piyasa")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.surface1, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showAssistant = true
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundStyle(Color.brandAccent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let vm, let updated = vm.lastUpdated {
                        Label(
                            updated.formatted(.dateTime.hour().minute()),
                            systemImage: "clock"
                        )
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .sheet(isPresented: $showAssistant) {
                AssistantChatView()
                    .environmentObject(appContainer)
            }
            .navigationDestination(item: $selectedStock) { company in
                StockDetailView(company: company)
            }
            .navigationDestination(item: $selectedSector) { sector in
                SectorDetailView(sector: sector, companies: companies)
            }
        }
        .onAppear {
            if vm == nil {
                vm = DashboardViewModel(
                    quoteRepo: appContainer.quoteRepository,
                    universeSymbols: { self.allSymbols }
                )
            }
        }
        .task(id: companies.count) {
            guard let vm, !allSymbols.isEmpty else { return }
            await vm.load(allSymbols: allSymbols)
        }
    }
}

// MARK: - Sector Strip
struct SectorStripSection: View {
    let vm: DashboardViewModel
    let onSectorTap: (Sector) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sektörler", icon: "chart.bar.fill")
                .padding(.horizontal, 16)

            if vm.isLoading {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<6, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.surface2)
                                .frame(width: 120, height: 64)
                                .skeleton()
                        }
                    }
                    .padding(.horizontal, 16)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(vm.sectors) { sector in
                            Button { onSectorTap(sector) } label: {
                                SectorChip(sector: sector)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }
}

struct SectorChip: View {
    let sector: Sector
    private var color: Color { Color.sectorColor(for: sector.name) }
    private var isPos: Bool { sector.changePercent >= 0 }

    var body: some View {
        HStack(spacing: 0) {
            // Colored left accent bar
            Rectangle()
                .fill(color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 5) {
                Text(sector.name)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                Text("\(sector.stockCount) hisse")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
                let sign = isPos ? "+" : ""
                Text("\(sign)\(String(format: "%.2f", sector.changePercent))%")
                    .font(.caption.monospaced().weight(.bold))
                    .foregroundStyle(isPos ? Color.positive : Color.negative)
            }
            .padding(.leading, 10)
            .padding(.trailing, 12)
            .padding(.vertical, 11)

            Spacer(minLength: 0)
        }
        .frame(width: 116)
        .background(Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Top Movers Section (horizontal cards)
struct TopMoversSection: View {
    let title: String
    let icon: String
    let iconColor: Color
    let quotes: [Quote]
    let companies: [Company]
    let onTap: (Company) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: title, icon: icon, iconColor: iconColor)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(quotes) { quote in
                        let company = companies.first { $0.symbol == quote.symbol }
                        MoverCard(quote: quote, company: company)
                            .onTapGesture {
                                if let c = company { onTap(c) }
                            }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct MoverCard: View {
    let quote: Quote
    let company: Company?

    private var color: Color { Color.sectorColor(for: company?.sector ?? "Diğer") }
    private var isPos: Bool { quote.changePercent >= 0 }
    private var trendColor: Color { isPos ? Color.positive : Color.negative }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top: badge + symbol
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Text(quote.symbol.prefix(3))
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(quote.symbol)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                    Text(company?.shortName ?? "—")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Price
            Text(quote.formattedPrice)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .padding(.bottom, 5)

            // Change badge
            let sign = isPos ? "+" : ""
            HStack(spacing: 3) {
                Image(systemName: isPos ? "arrow.up" : "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                Text("\(sign)\(String(format: "%.2f", quote.changePercent))%")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(trendColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(trendColor.opacity(0.14))
            .clipShape(Capsule())
        }
        .padding(13)
        .frame(width: 140, height: 120)
        .background(Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(
                    LinearGradient(
                        colors: [trendColor.opacity(0.35), trendColor.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Volume Section (list style)
struct VolumeSection: View {
    let quotes: [Quote]
    let companies: [Company]
    let onTap: (Company) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Hacim Öncüleri", icon: "waveform.path.ecg", iconColor: .brandAccent)
                .padding(.horizontal, 16)

            VStack(spacing: 6) {
                ForEach(quotes) { quote in
                    let company = companies.first { $0.symbol == quote.symbol }
                    VolumeRow(quote: quote, company: company, maxVolume: quotes.first?.volumeTL ?? 1)
                        .onTapGesture {
                            if let c = company { onTap(c) }
                        }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

struct VolumeRow: View {
    let quote: Quote
    let company: Company?
    let maxVolume: Double

    private var fillRatio: CGFloat {
        guard maxVolume > 0 else { return 0 }
        return CGFloat(min(quote.volumeTL / maxVolume, 1.0))
    }
    private var isPos: Bool { quote.changePercent >= 0 }

    var body: some View {
        HStack(spacing: 12) {
            SymbolBadge(symbol: quote.symbol, sector: company?.sector ?? "Diğer")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(quote.symbol)
                        .font(.callout.monospaced().weight(.bold))
                        .foregroundStyle(Color.textPrimary)
                    let sign = isPos ? "+" : ""
                    Text("\(sign)\(String(format: "%.1f", quote.changePercent))%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isPos ? Color.positive : Color.negative)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.brandAccent.opacity(0.12))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [Color.brandAccent, Color.brandAccent.opacity(0.5)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * fillRatio, height: 4)
                    }
                }
                .frame(height: 4)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(quote.formattedPrice)
                    .font(.callout.monospaced().weight(.semibold))
                    .foregroundStyle(Color.textPrimary)
                Text(quote.formattedVolume)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.surface3, lineWidth: 1)
        )
    }
}

// MARK: - BIST Index Section
struct BISTIndexSection: View {
    let vm: DashboardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "BIST Endeksleri", icon: "chart.bar.xaxis")
                .padding(.horizontal, 16)

            if vm.isLoading {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.surface2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 80)
                            .skeleton()
                    }
                }
                .padding(.horizontal, 16)
            } else if vm.bistIndices.isEmpty {
                Text("Endeks verisi alınamadı")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                HStack(spacing: 12) {
                    ForEach(vm.bistIndices) { index in
                        BISTIndexCard(index: index)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

struct BISTIndexCard: View {
    let index: BISTIndex
    private var trendColor: Color { index.isPositive ? Color.positive : Color.negative }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Full-height colored accent bar
                Rectangle()
                    .fill(trendColor)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 10) {
                    // Symbol + name
                    VStack(alignment: .leading, spacing: 2) {
                        Text(index.symbol)
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                        Text(index.name)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                    }

                    // Value
                    Text(index.formattedValue)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)

                    // Change badge with arrow
                    let sign = index.changePercent >= 0 ? "+" : ""
                    HStack(spacing: 3) {
                        Image(systemName: index.isPositive ? "arrow.up" : "arrow.down")
                            .font(.system(size: 8, weight: .bold))
                        Text("\(sign)\(String(format: "%.2f", index.changePercent))%")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .foregroundStyle(trendColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(trendColor.opacity(0.14))
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 104)
        .background(Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(trendColor.opacity(0.18), lineWidth: 1)
        )
    }
}


