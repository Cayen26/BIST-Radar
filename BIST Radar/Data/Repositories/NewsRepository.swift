// NewsRepository.swift – News feed with live RSS + mock fallback
// BIST Radar AI

import Foundation
import Combine

@MainActor
final class NewsRepository: ObservableObject {
    private let provider: any MarketDataProvider
    private let rss = RSSNewsFetcher.shared

    init(provider: any MarketDataProvider) {
        self.provider = provider
    }

    // MARK: - Fetch articles

    func articles(symbol: String? = nil) async throws -> [NewsArticle] {
        // Default true: first-launch key not yet set → live news on
        let liveEnabled = UserDefaults.standard.object(forKey: "liveNewsEnabled") as? Bool ?? true
        let key = "news_\(symbol ?? "all")_\(liveEnabled ? "live" : "mock")"

        // Memory cache
        if let mem = AppCaches.news.value(forKey: key) { return mem }

        var fetched: [NewsArticle]

        if liveEnabled && symbol == nil {
            // Try live RSS; fall back to mock on any error
            let rssArticles = await rss.fetchAll()
            fetched = rssArticles.isEmpty
                ? (try? await provider.fetchNews(symbol: nil)) ?? []
                : rssArticles
        } else {
            fetched = try await provider.fetchNews(symbol: symbol)
        }

        let sorted = fetched.sorted { $0.publishedAt > $1.publishedAt }
        AppCaches.news.set(sorted, forKey: key, ttl: AppCaches.newsTTL)
        return sorted
    }

    func invalidate() {
        AppCaches.news.removeAll()
    }
}

