// NewsView.swift – Financial news feed
// BIST Radar AI

import SwiftUI

struct NewsView: View {
    @EnvironmentObject var appContainer: AppContainer
    @State private var vm: NewsViewModel?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface1.ignoresSafeArea()

                if let vm {
                    NewsContentView(vm: vm)
                } else {
                    ProgressView("Yükleniyor...")
                        .foregroundStyle(Color.textSecondary)
                }
            }
            .navigationTitle("Haberler")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.surface1, for: .navigationBar)
        }
        .onAppear {
            if vm == nil {
                vm = NewsViewModel(newsRepo: appContainer.newsRepository)
            }
            Task { await vm?.load() }
        }
    }
}

// MARK: - Main Content

struct NewsContentView: View {
    let vm: NewsViewModel
    @State private var selectedArticle: NewsArticle?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Breaking news banner
                if !vm.breaking.isEmpty {
                    BreakingNewsBanner(articles: vm.breaking) { article in
                        selectedArticle = article
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                }

                // Category filter strip
                NewsCategoryFilter(
                    selected: vm.selectedCategory,
                    onSelect: { vm.selectedCategory = $0 }
                )

                Divider().overlay(Color.surface3).padding(.horizontal, 16)

                // Article list
                if vm.isLoading && vm.filtered.isEmpty {
                    ForEach(0..<8, id: \.self) { _ in
                        NewsRowSkeleton()
                        Divider().overlay(Color.surface3).padding(.horizontal, 16)
                    }
                } else if vm.filtered.isEmpty {
                    ContentUnavailableView(
                        "Haber Bulunamadı",
                        systemImage: "newspaper",
                        description: Text("Bu kategoride henüz haber yok.")
                    )
                    .padding(.top, 60)
                } else {
                    ForEach(vm.filtered) { article in
                        Button {
                            selectedArticle = article
                        } label: {
                            NewsArticleRow(article: article)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)

                        if article.id != vm.filtered.last?.id {
                            Divider().overlay(Color.surface3).padding(.horizontal, 16)
                        }
                    }
                }

                Spacer(minLength: 32)
            }
        }
        .refreshable { await vm.load() }
        .sheet(item: $selectedArticle) { article in
            NewsDetailSheet(article: article)
        }
    }
}

// MARK: - Breaking News Banner

struct BreakingNewsBanner: View {
    let articles: [NewsArticle]
    let onTap: (NewsArticle) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.negative)
                    .frame(width: 7, height: 7)
                Text("SON DAKİKA")
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.negative)
                    .kerning(1.0)
                Spacer()
            }

            ForEach(articles.prefix(2)) { article in
                Button { onTap(article) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.negative)
                            .frame(width: 3)
                            .frame(minHeight: 16)
                        Text(article.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.textPrimary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.negative.opacity(0.07))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.negative.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Category Filter

struct NewsCategoryFilter: View {
    let selected: NewsCategory?
    let onSelect: (NewsCategory?) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                NewsCategoryChip(
                    label: "Tümü",
                    icon: "list.bullet",
                    isSelected: selected == nil
                ) { onSelect(nil) }

                ForEach(NewsCategory.allCases, id: \.self) { cat in
                    NewsCategoryChip(
                        label: cat.displayName,
                        icon: cat.icon,
                        isSelected: selected == cat
                    ) { onSelect(cat) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

struct NewsCategoryChip: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isSelected ? Color.brandAccent : Color.surface2)
            .clipShape(Capsule())
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Article Row

struct NewsArticleRow: View {
    let article: NewsArticle

    private var catColor: Color { Color(hex: article.category.color) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category + time
            HStack(spacing: 5) {
                Image(systemName: article.category.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(catColor)
                Text(article.category.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(catColor)
                Spacer()
                if article.isBreaking {
                    Text("SON DAKİKA")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color.negative)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.negative.opacity(0.12))
                        .clipShape(Capsule())
                }
                Text(article.timeAgo)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.textTertiary)
            }

            // Title
            Text(article.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)

            // Summary
            Text(article.summary)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)

            // Source + related symbols
            HStack(spacing: 6) {
                Image(systemName: "newspaper")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
                Text(article.source)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.textTertiary)

                if !article.relatedSymbols.isEmpty {
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(article.relatedSymbols.prefix(3), id: \.self) { sym in
                            Text(sym)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.brandAccent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.brandAccent.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

// MARK: - Skeleton Row

struct NewsRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 4).fill(Color.surface2)
                .frame(width: 90, height: 10).skeleton()
            RoundedRectangle(cornerRadius: 4).fill(Color.surface2)
                .frame(maxWidth: .infinity).frame(height: 14).skeleton()
            RoundedRectangle(cornerRadius: 4).fill(Color.surface2)
                .frame(maxWidth: .infinity).frame(height: 12).skeleton()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - Detail Sheet

struct NewsDetailSheet: View {
    let article: NewsArticle
    @Environment(\.dismiss) private var dismiss

    private var catColor: Color { Color(hex: article.category.color) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Category + time row
                    HStack(spacing: 6) {
                        Image(systemName: article.category.icon)
                            .foregroundStyle(catColor)
                        Text(article.category.displayName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(catColor)
                        Spacer()
                        Text(article.timeAgo)
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }

                    // Title
                    Text(article.title)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.textPrimary)

                    Divider().overlay(Color.surface3)

                    // Body
                    Text(article.summary)
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .lineSpacing(5)

                    // Source
                    HStack(spacing: 6) {
                        Image(systemName: "newspaper")
                            .foregroundStyle(Color.textTertiary)
                        Text("Kaynak: \(article.source)")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }

                    // Related symbols
                    if !article.relatedSymbols.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("İlgili Hisseler")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.textSecondary)
                            HStack(spacing: 8) {
                                ForEach(article.relatedSymbols, id: \.self) { sym in
                                    Text(sym)
                                        .font(.system(.caption, design: .monospaced, weight: .bold))
                                        .foregroundStyle(Color.brandAccent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(Color.brandAccent.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    // Disclaimer
                    Text("Bu içerik yalnızca bilgilendirme amaçlıdır. Yatırım tavsiyesi değildir.")
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .background(Color.surface1)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(Color.brandAccent)
                }
            }
        }
    }
}
