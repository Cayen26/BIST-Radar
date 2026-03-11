// NewsViewModel.swift
// BIST Radar AI

import SwiftUI
import Observation

@Observable
final class NewsViewModel {
    var articles: [NewsArticle] = []
    var isLoading = false
    var error: String?
    var selectedCategory: NewsCategory? = nil  // nil = tümü

    private let newsRepo: NewsRepository

    init(newsRepo: NewsRepository) {
        self.newsRepo = newsRepo
    }

    var filtered: [NewsArticle] {
        guard let cat = selectedCategory else { return articles }
        return articles.filter { $0.category == cat }
    }

    var breaking: [NewsArticle] {
        articles.filter { $0.isBreaking }
    }

    @MainActor
    func load() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            articles = try await newsRepo.articles()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
