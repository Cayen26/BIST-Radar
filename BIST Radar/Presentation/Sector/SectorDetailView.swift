// SectorDetailView.swift – Sector detail with stock rankings
// BIST Radar AI

import SwiftUI

struct SectorDetailView: View {
    let sector: Sector
    let companies: [Company]

    @EnvironmentObject var appContainer: AppContainer
    @State private var vm: SectorDetailViewModel?
    @State private var selectedStock: Company?

    private var sectorCompanies: [Company] {
        companies.filter { $0.sector == sector.name && $0.isActive }
    }

    private var sectorColor: Color { Color.sectorColor(for: sector.name) }

    var body: some View {
        ZStack {
            Color.surface1.ignoresSafeArea()

            if let vm {
                ScrollView {
                    VStack(spacing: 16) {
                        // Sector header card
                        SectorHeaderCard(sector: sector, vm: vm)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        // Stats row
                        if !vm.isLoading {
                            SectorStatsRow(vm: vm)
                                .padding(.horizontal, 16)
                        }

                        // Stock list
                        SectorStockList(
                            vm: vm,
                            companies: sectorCompanies,
                            onTap: { selectedStock = $0 }
                        )
                        .padding(.horizontal, 16)

                        Spacer(minLength: 24)
                    }
                }
                .refreshable {
                    await vm.load(symbols: sectorCompanies.map(\.symbol))
                }
            } else {
                ProgressView("Yükleniyor...")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .navigationTitle(sector.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.surface1, for: .navigationBar)
        .navigationDestination(item: $selectedStock) { company in
            StockDetailView(company: company)
        }
        .onAppear {
            if vm == nil {
                vm = SectorDetailViewModel(quoteRepo: appContainer.quoteRepository)
            }
            Task { await vm?.load(symbols: sectorCompanies.map(\.symbol)) }
        }
    }
}

// MARK: - Header Card

struct SectorHeaderCard: View {
    let sector: Sector
    let vm: SectorDetailViewModel

    private var color: Color { Color.sectorColor(for: sector.name) }

    var body: some View {
        HStack(spacing: 16) {
            // Sector icon circle
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 56, height: 56)
                Circle()
                    .stroke(color.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 56, height: 56)
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(sector.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: 10) {
                    ChangeBadge(value: sector.changePercent)

                    Text("\(vm.isLoading ? sector.stockCount : vm.quotes.count) hisse")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()
        }
        .padding(16)
        .background(Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Stats Row

struct SectorStatsRow: View {
    let vm: SectorDetailViewModel

    var body: some View {
        HStack(spacing: 12) {
            SectorStatCard(
                title: "Yükselen",
                value: "\(vm.gainers.count)",
                color: .positive,
                icon: "arrow.up.circle.fill"
            )
            SectorStatCard(
                title: "Düşen",
                value: "\(vm.losers.count)",
                color: .negative,
                icon: "arrow.down.circle.fill"
            )
            SectorStatCard(
                title: "Ort. Değ.",
                value: (vm.avgChange >= 0 ? "+" : "") + String(format: "%.2f%%", vm.avgChange),
                color: vm.avgChange >= 0 ? .positive : .negative,
                icon: "percent"
            )
        }
    }
}

struct SectorStatCard: View {
    let title: String
    let value: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(value)
                .font(.system(.callout, design: .monospaced, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Stock List

struct SectorStockList: View {
    let vm: SectorDetailViewModel
    let companies: [Company]
    let onTap: (Company) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sektör Hisseleri", icon: "list.bullet.rectangle.fill")

            if vm.isLoading && vm.quotes.isEmpty {
                ForEach(0..<6, id: \.self) { _ in
                    StockRowSkeleton()
                }
            } else if vm.quotes.isEmpty {
                ContentUnavailableView(
                    "Veri Yok",
                    systemImage: "chart.bar",
                    description: Text("Bu sektör için veri bulunamadı.")
                )
                .padding(.top, 20)
            } else {
                // Sort companies by their quote's changePercent
                let sorted = companies.sorted { a, b in
                    let qa = vm.quote(for: a.symbol)?.changePercent ?? 0
                    let qb = vm.quote(for: b.symbol)?.changePercent ?? 0
                    return qa > qb
                }

                ForEach(sorted) { company in
                    StockRowView(
                        company: company,
                        quote: vm.quote(for: company.symbol),
                        isInWatchlist: false,
                        onTap: { onTap(company) }
                    )
                }
            }
        }
    }
}
