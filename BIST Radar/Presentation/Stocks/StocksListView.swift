// StocksListView.swift – Full BIST universe list with search & filter
// BIST Radar AI

import SwiftUI
import SwiftData

struct StocksListView: View {
    @EnvironmentObject var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Company.symbol) private var allCompanies: [Company]

    @State private var vm: StocksListViewModel?
    @State private var selectedCompany: Company?
    @State private var showFilters = false

    // Visible symbols for quote loading
    @State private var visibleSymbols: Set<String> = []

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface1.ignoresSafeArea()

                Group {
                    if let vm {
                        let filtered = vm.filtered(companies: allCompanies)
                        stocksList(vm: vm, companies: filtered)
                    } else {
                        ProgressView()
                    }
                }
            }
            .navigationTitle("Hisseler")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.surface1, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle.fill")
                            .foregroundStyle(hasActiveFilter ? Color.brandAccent : Color.textSecondary)
                    }
                }
            }
            .searchable(
                text: Binding(
                    get: { vm?.searchText ?? "" },
                    set: { vm?.searchText = $0 }
                ),
                placement: .navigationBarDrawer,
                prompt: "Sembol veya şirket adı ara..."
            )
            .navigationDestination(item: $selectedCompany) { company in
                StockDetailView(company: company)
            }
            .sheet(isPresented: $showFilters) {
                if let vm { StockFilterSheet(vm: vm, sectors: availableSectors) }
            }
        }
        .onAppear {
            if vm == nil {
                vm = StocksListViewModel(quoteRepo: appContainer.quoteRepository)
            }
        }
    }

    private var hasActiveFilter: Bool {
        vm?.filter.sector != nil ||
        vm?.filter.marketSegment != nil ||
        vm?.filter.indexFilter != nil ||
        vm?.sortOption != .symbol
    }

    private var availableSectors: [String] {
        Array(Set(allCompanies.map { $0.sector })).sorted()
    }

    @ViewBuilder
    private func stocksList(vm: StocksListViewModel, companies: [Company]) -> some View {
        List {
            // Results count
            Section {
                Text("\(companies.count) sonuç")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .listRowBackground(Color.surface1)
                    .listRowSeparator(.hidden)
            }

            ForEach(companies) { company in
                let quote = vm.quotesBySymbol[company.symbol]
                let isWatchlisted = appContainer.watchlistRepository.contains(
                    symbol: company.symbol, modelContext: modelContext
                )

                StockRowView(
                    company: company,
                    quote: quote,
                    isInWatchlist: isWatchlisted,
                    onTap: { selectedCompany = company },
                    onWatchlistToggle: {
                        appContainer.watchlistRepository.toggle(
                            symbol: company.symbol,
                            companyNameTr: company.companyNameTr,
                            modelContext: modelContext
                        )
                    }
                )
                .listRowBackground(Color.surface1)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                .onAppear {
                    visibleSymbols.insert(company.symbol)
                    // Load in batches of 30 as user scrolls
                    let unloaded = visibleSymbols.filter { vm.quotesBySymbol[$0] == nil }
                    if unloaded.count >= 20 {
                        let toLoad = Array(unloaded)
                        Task { await vm.loadQuotes(for: toLoad) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .background(Color.surface1)
        .scrollContentBackground(.hidden)
        .task(id: companies.map(\.symbol).joined()) {
            // Load first batch immediately when company list changes
            let symbols = companies.prefix(40).map(\.symbol).filter {
                vm.quotesBySymbol[$0] == nil
            }
            if !symbols.isEmpty {
                await vm.loadQuotes(for: Array(symbols))
            }
        }
    }
}

// MARK: - Filter Sheet
struct StockFilterSheet: View {
    @Bindable var vm: StocksListViewModel
    let sectors: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface1.ignoresSafeArea()

                Form {
                    Section("Sıralama") {
                        Picker("Sırala", selection: $vm.sortOption) {
                            ForEach(StocksListViewModel.SortOption.allCases, id: \.self) {
                                Text($0.rawValue).tag($0)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .listRowBackground(Color.surface2)

                    Section("Endeks Filtresi") {
                        Picker("Endeks", selection: $vm.filter.indexFilter) {
                            Text("Tümü").tag(Optional<StockFilter.IndexFilter>.none)
                            ForEach(StockFilter.IndexFilter.allCases, id: \.self) { idx in
                                Text(idx.rawValue).tag(Optional(idx))
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowBackground(Color.surface2)

                    Section("Sektör") {
                        Picker("Sektör", selection: $vm.filter.sector) {
                            Text("Tümü").tag(Optional<String>.none)
                            ForEach(sectors, id: \.self) { s in
                                Text(s).tag(Optional(s))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .listRowBackground(Color.surface2)

                    Section("Pazar") {
                        Picker("Pazar", selection: $vm.filter.marketSegment) {
                            Text("Tümü").tag(Optional<String>.none)
                            Text("Yıldız Pazar").tag(Optional("Yıldız"))
                            Text("Ana Pazar").tag(Optional("Ana"))
                            Text("Alt Pazar").tag(Optional("Alt"))
                        }
                        .pickerStyle(.menu)
                    }
                    .listRowBackground(Color.surface2)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Filtrele & Sırala")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sıfırla") { vm.resetFilter() }
                        .foregroundStyle(Color.negative)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Tamam") { dismiss() }
                        .foregroundStyle(Color.brandAccent)
                }
            }
        }
    }
}
