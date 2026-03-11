// UniverseRepository.swift – Universe fetch + SwiftData persistence + search
// BIST Radar AI

import Foundation
import SwiftData
import Combine

@MainActor
final class UniverseRepository: ObservableObject {
    private let provider: any MarketDataProvider
    private let staleTTL: TimeInterval = 0  // Her açılışta JSON'dan taze yükle

    @Published var isLoading = false
    @Published var error: String?

    init(provider: any MarketDataProvider) {
        self.provider = provider
    }

    // MARK: - Fetch and persist universe
    func refreshIfNeeded(modelContext: ModelContext) async {
        let descriptor = FetchDescriptor<Company>(
            sortBy: [SortDescriptor(\Company.symbol)]
        )
        let stored = (try? modelContext.fetch(descriptor)) ?? []
        let lastUpdated = stored.first?.updatedAt ?? .distantPast
        let isStale = staleTTL == 0 || Date().timeIntervalSince(lastUpdated) > staleTTL

        // Always refresh if empty, stale, or provider might have more data
        if stored.isEmpty || isStale {
            await forceRefresh(modelContext: modelContext)
        }
    }

    func forceRefresh(modelContext: ModelContext) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let dtos = try await provider.fetchUniverse()
            await persist(dtos: dtos, modelContext: modelContext)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Search with Turkish normalization
    func search(
        query: String,
        filter: StockFilter,
        modelContext: ModelContext
    ) -> [Company] {
        let norm = query.turkishNormalized()
        var descriptor = FetchDescriptor<Company>()

        // Build predicate
        var predicates: [Predicate<Company>] = []

        if filter.onlyActive {
            predicates.append(#Predicate<Company> { $0.isActive == true })
        }
        if let segment = filter.marketSegment, !segment.isEmpty {
            predicates.append(#Predicate<Company> { $0.marketSegment == segment })
        }
        if let sector = filter.sector, !sector.isEmpty {
            predicates.append(#Predicate<Company> { $0.sector == sector })
        }
        if let index = filter.indexFilter {
            switch index {
            case .bist30:
                predicates.append(#Predicate<Company> { $0.inBIST30 == true })
            case .bist50:
                predicates.append(#Predicate<Company> { $0.inBIST50 == true })
            case .bist100:
                predicates.append(#Predicate<Company> { $0.inBIST100 == true })
            case .all:
                break
            }
        }

        if !predicates.isEmpty {
            descriptor.predicate = predicates.dropFirst().reduce(predicates[0]) { combined, next in
                #Predicate<Company> { c in combined.evaluate(c) && next.evaluate(c) }
            }
        }

        var results = (try? modelContext.fetch(descriptor)) ?? []

        // Turkish normalized search
        if !norm.isEmpty {
            results = results.filter {
                $0.symbolNorm.contains(norm) || $0.nameNorm.contains(norm)
            }
        }

        return results.sorted { $0.symbol < $1.symbol }
    }

    func allSectors(modelContext: ModelContext) -> [String] {
        let descriptor = FetchDescriptor<Company>()
        let all = (try? modelContext.fetch(descriptor)) ?? []
        return Array(Set(all.map { $0.sector })).sorted()
    }

    // MARK: - Persist
    private func persist(dtos: [CompanyDTO], modelContext: ModelContext) async {
        // Clear existing
        let existing = (try? modelContext.fetch(FetchDescriptor<Company>())) ?? []
        existing.forEach { modelContext.delete($0) }

        // Insert updated records
        for dto in dtos {
            let company = dto.toModel()
            modelContext.insert(company)
        }

        try? modelContext.save()
    }
}
