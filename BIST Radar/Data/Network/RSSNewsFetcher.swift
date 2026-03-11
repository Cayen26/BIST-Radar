// RSSNewsFetcher.swift – Fetches real financial news from RSS feeds
// BIST Radar AI

import Foundation

// MARK: - Feed Catalogue

enum NewsFeed: String, CaseIterable, Sendable {
    case bloombergHT  = "Bloomberg HT"
    case investing    = "Investing.com TR"

    var url: URL? {
        switch self {
        case .bloombergHT:
            return URL(string: "https://www.bloomberght.com/rss")
        case .investing:
            return URL(string: "https://tr.investing.com/rss/news.rss")
        }
    }

    var icon: String {
        switch self {
        case .bloombergHT: return "newspaper.fill"
        case .investing:   return "chart.line.uptrend.xyaxis"
        }
    }
}

// MARK: - Fetcher

final class RSSNewsFetcher: Sendable {
    static let shared = RSSNewsFetcher()
    private init() {}

    /// Fetch from all enabled feeds, deduplicate, sort newest-first.
    func fetchAll(enabledFeeds: [NewsFeed] = NewsFeed.allCases) async -> [NewsArticle] {
        var all: [NewsArticle] = []

        await withTaskGroup(of: [NewsArticle].self) { group in
            for feed in enabledFeeds {
                guard let url = feed.url else { continue }
                group.addTask { [self] in
                    (try? await self.fetch(url: url, source: feed.rawValue)) ?? []
                }
            }
            for await articles in group {
                all.append(contentsOf: articles)
            }
        }

        var seen = Set<String>()
        return all
            .filter { seen.insert($0.title).inserted }
            .sorted { $0.publishedAt > $1.publishedAt }
    }

    private func fetch(url: URL, source: String) async throws -> [NewsArticle] {
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("BIST-Radar/1.0 CFNetwork", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        return RSSParser(source: source).parse(data: data)
    }
}

// MARK: - XML Parser

private final class RSSParser: NSObject, XMLParserDelegate {
    private let source: String
    private(set) var result: [NewsArticle] = []

    // Per-item state
    private var inItem   = false
    private var buf      = ""
    private var title    = ""
    private var desc     = ""
    private var pubDate  = ""
    private var catText  = ""

    init(source: String) { self.source = source }

    func parse(data: Data) -> [NewsArticle] {
        let p = XMLParser(data: data)
        p.delegate = self
        p.parse()
        return result
    }

    // MARK: XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement name: String,
                namespaceURI: String?,
                qualifiedName: String?,
                attributes: [String: String] = [:]) {
        buf = ""
        if name == "item" || name == "entry" { inItem = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buf += string
    }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        buf += String(data: data, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser,
                didEndElement name: String,
                namespaceURI: String?,
                qualifiedName: String?) {
        let t = buf.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inItem else { return }

        switch name {
        case "title":
            title = stripped(t)
        case "description", "summary", "content:encoded":
            if desc.isEmpty { desc = stripped(t) }
        case "pubDate", "published", "dc:date", "updated":
            pubDate = t
        case "category", "dc:subject":
            catText = t
        case "item", "entry":
            if !title.isEmpty { result.append(makeArticle()) }
            title = ""; desc = ""; pubDate = ""; catText = ""
            inItem = false
        default:
            break
        }
    }

    // MARK: Build article

    private func makeArticle() -> NewsArticle {
        let body = desc.isEmpty ? "Haberin tamamı için kaynağı ziyaret edin." : String(desc.prefix(350))
        return NewsArticle(
            id: UUID().uuidString,
            title: title,
            summary: body,
            source: source,
            category: classify(title: title, desc: desc, cat: catText),
            relatedSymbols: detectSymbols(title + " " + desc),
            publishedAt: parseDate(pubDate),
            isBreaking: false
        )
    }

    // MARK: Category classifier

    private func classify(title: String, desc: String, cat: String) -> NewsCategory {
        let s = (title + " " + desc + " " + cat).lowercased()
        if s.contains("kap ") || s.contains("kamuoyu") || s.contains("özel durum") ||
           s.contains("bildiri") || s.contains("disclosure") {
            return .kapDisclosure
        }
        if s.contains("faiz") || s.contains("merkez bank") || s.contains("enflasyon") ||
           s.contains("bütçe") || s.contains("büyüme") || s.contains("cari açık") ||
           s.contains("gsyih") || s.contains("ekonomi") && s.contains("politika") {
            return .economy
        }
        if s.contains("fed ") || s.contains("ecb") || s.contains("küresel") ||
           s.contains("abd ") || s.contains("avrupa piyasa") || s.contains("asya piyasa") ||
           s.contains("dolar endeks") || s.contains("çin") {
            return .world
        }
        if s.contains("sektör") || s.contains("bankacılık") || s.contains("enerji sektör") ||
           s.contains("teknoloji") || s.contains("sanayi") {
            return .sector
        }
        return .market
    }

    // MARK: Symbol detection

    private static let knownSymbols: [String] = [
        "THYAO","GARAN","AKBNK","EREGL","BIMAS","TUPRS","ASELS","TOASO","SISE",
        "KCHOL","PETKM","VAKBN","ISCTR","HALKB","TKFEN","ENKAI","FROTO","SAHOL",
        "ARCLK","TCELL","KOZAL","MGROS","MAVI","LOGO","EKGYO","ULKER","TTRAK",
        "VESBE","GUBRF","AGHOL","PGSUS","CIMSA","BRISA","DOHOL","ALKIM","SOKM",
        "BIOEN","SODA","TRKCM","NTHOL","KCAER","OYAKC","KLMSN","BFREN"
    ]

    private func detectSymbols(_ text: String) -> [String] {
        Self.knownSymbols.filter { text.contains($0) }
    }

    // MARK: Date parsing

    private static let dateFormats = [
        "EEE, dd MMM yyyy HH:mm:ss Z",
        "EEE, dd MMM yyyy HH:mm:ss zzz",
        "yyyy-MM-dd'T'HH:mm:ssZ",
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd HH:mm:ss",
    ]

    private static let dateFormatters: [DateFormatter] = dateFormats.map { fmt in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = fmt
        return f
    }

    private func parseDate(_ str: String) -> Date {
        for f in Self.dateFormatters {
            if let d = f.date(from: str) { return d }
        }
        return Date()
    }

    // MARK: HTML stripping

    private func stripped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;",  with: "&")
            .replacingOccurrences(of: "&lt;",   with: "<")
            .replacingOccurrences(of: "&gt;",   with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;",  with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\n{2,}", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
