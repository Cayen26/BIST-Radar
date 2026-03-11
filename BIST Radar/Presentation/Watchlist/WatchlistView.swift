// WatchlistView.swift – User's favorite stocks with quick insights
// BIST Radar AI

import SwiftUI
import SwiftData

struct WatchlistView: View {
    @EnvironmentObject var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WatchlistItem.sortOrder) private var watchlistItems: [WatchlistItem]
    @Query(sort: \Company.symbol) private var allCompanies: [Company]

    @State private var quotesBySymbol: [String: Quote] = [:]
    @State private var isLoadingQuotes = false
    @State private var selectedCompany: Company?
    @State private var showAssistant = false

    private var watchlistCompanies: [Company] {
        let symbols = Set(watchlistItems.map { $0.symbol })
        return allCompanies.filter { symbols.contains($0.symbol) }
            .sorted { $0.symbol < $1.symbol }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface1.ignoresSafeArea()

                if watchlistItems.isEmpty {
                    EmptyWatchlistView()
                } else {
                    List {
                        ForEach(watchlistCompanies) { company in
                            let q = quotesBySymbol[company.symbol]
                            StockRowView(
                                company: company,
                                quote: q,
                                isInWatchlist: true,
                                onTap: { selectedCompany = company },
                                onWatchlistToggle: {
                                    appContainer.watchlistRepository.remove(
                                        symbol: company.symbol,
                                        modelContext: modelContext
                                    )
                                }
                            )
                            .listRowBackground(Color.surface1)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 0))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable { await loadQuotes() }
                }
            }
            .navigationTitle("İzleme Listesi")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.surface1, for: .navigationBar)
            .toolbar {
                if !watchlistItems.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAssistant = true
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .foregroundStyle(Color.brandAccent)
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedCompany) { company in
                StockDetailView(company: company)
            }
            .sheet(isPresented: $showAssistant) {
                AssistantChatView()
            }
            .task { await loadQuotes() }
            .onChange(of: watchlistItems.count) { _, _ in
                Task { await loadQuotes() }
            }
        }
    }

    private func loadQuotes() async {
        let symbols = watchlistItems.map { $0.symbol }
        guard !symbols.isEmpty else { return }
        isLoadingQuotes = true
        defer { isLoadingQuotes = false }
        do {
            let quotes = try await appContainer.quoteRepository.quotes(for: symbols)
            await MainActor.run {
                for q in quotes { quotesBySymbol[q.symbol] = q }
            }
        } catch { }
    }
}

// MARK: - Empty state
struct EmptyWatchlistView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "star.slash")
                .font(.system(size: 60, weight: .thin))
                .foregroundStyle(Color.textTertiary)

            Text("İzleme Listeniz Boş")
                .font(.title2.bold())
                .foregroundStyle(Color.textPrimary)

            Text("Hisseler listesinde bir hissenin yanındaki yıldız simgesine dokunarak ekleyebilirsiniz.")
                .font(.callout)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}
