// ChatMessage.swift – Assistant chat message model
// BIST Radar AI

import Foundation

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: MessageRole
    var content: String
    let timestamp: Date
    var isLoading: Bool        // shows typing indicator
    let relatedSymbol: String? // context symbol if any

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        isLoading: Bool = false,
        relatedSymbol: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isLoading = isLoading
        self.relatedSymbol = relatedSymbol
    }

    static func userMessage(_ text: String, symbol: String? = nil) -> ChatMessage {
        ChatMessage(role: .user, content: text, relatedSymbol: symbol)
    }

    static func loadingMessage() -> ChatMessage {
        ChatMessage(role: .assistant, content: "", isLoading: true)
    }

    static func assistantMessage(_ text: String, symbol: String? = nil) -> ChatMessage {
        ChatMessage(role: .assistant, content: text, relatedSymbol: symbol)
    }
}

// MARK: - Quick action chips
struct QuickChip: Identifiable, Sendable {
    let id = UUID()
    let label: String
    let query: String
    let category: String
}

extension QuickChip {
    static let defaults: [QuickChip] = [
        // ── Teknik Göstergeler ──
        QuickChip(label: "📊 RSI",             query: "RSI göstergesi nedir ve nasıl yorumlanır?",                    category: "📊 Teknik Göstergeler"),
        QuickChip(label: "🔁 MACD",            query: "MACD göstergesi nedir ve nasıl kullanılır?",                  category: "📊 Teknik Göstergeler"),
        QuickChip(label: "📉 Bollinger",        query: "Bollinger Bantları nedir ve nasıl yorumlanır?",               category: "📊 Teknik Göstergeler"),
        QuickChip(label: "⚡ StochRSI",         query: "Stochastic RSI nedir ve RSI'dan farkı nedir?",               category: "📊 Teknik Göstergeler"),
        QuickChip(label: "📈 EMA vs SMA",       query: "EMA ile SMA arasındaki fark nedir? Hangisi daha kullanışlı?",category: "📊 Teknik Göstergeler"),
        QuickChip(label: "🎯 Destek/Direnç",   query: "Destek ve direnç seviyeleri nedir, nasıl belirlenir?",        category: "📊 Teknik Göstergeler"),
        QuickChip(label: "📐 Fibonacci",        query: "Fibonacci düzeltme seviyeleri nedir ve nasıl kullanılır?",   category: "📊 Teknik Göstergeler"),
        QuickChip(label: "🌟 Golden Cross",     query: "Golden Cross nedir, nasıl yorumlanır?",                      category: "📊 Teknik Göstergeler"),
        QuickChip(label: "💀 Death Cross",      query: "Death Cross nedir ve ne anlama gelir?",                      category: "📊 Teknik Göstergeler"),
        QuickChip(label: "📊 Pivot Noktaları",  query: "Pivot noktaları (PP, R1, R2, S1, S2) nedir?",               category: "📊 Teknik Göstergeler"),
        QuickChip(label: "🕯️ Mum Formasyonu",  query: "Önemli Japon mum formasyonları nelerdir?",                  category: "📊 Teknik Göstergeler"),
        QuickChip(label: "📦 Hacim Analizi",    query: "Hacim analizi nedir ve fiyat hareketleriyle ilişkisi nedir?",category: "📊 Teknik Göstergeler"),
        QuickChip(label: "🔺 ATR",              query: "ATR (Average True Range) nedir ve nasıl hesaplanır?",        category: "📊 Teknik Göstergeler"),
        QuickChip(label: "🔃 Trend Analizi",    query: "Trend analizi nedir? Yükselen, düşen ve yatay trend nedir?",category: "📊 Teknik Göstergeler"),
        QuickChip(label: "💧 Likidite",         query: "Piyasada likidite nedir ve neden önemlidir?",               category: "📊 Teknik Göstergeler"),
        QuickChip(label: "🔔 Kırılım",          query: "Direnç ve destek kırılımı nedir, nasıl onaylanır?",         category: "📊 Teknik Göstergeler"),

        // ── Temel Analiz ──
        QuickChip(label: "🏦 F/K Oranı",       query: "F/K (Fiyat/Kazanç) oranı nedir ve nasıl yorumlanır?",       category: "📋 Temel Analiz"),
        QuickChip(label: "📚 PD/DD",            query: "PD/DD oranı nedir ve düşük/yüksek olması ne anlama gelir?", category: "📋 Temel Analiz"),
        QuickChip(label: "💹 EV/EBITDA",        query: "EV/EBITDA oranı nedir?",                                    category: "📋 Temel Analiz"),
        QuickChip(label: "💰 Temettü",          query: "Temettü nedir, temettü verimi nasıl hesaplanır?",           category: "📋 Temel Analiz"),
        QuickChip(label: "📊 ROE / ROA",        query: "ROE ve ROA nedir, aralarındaki fark nedir?",                category: "📋 Temel Analiz"),
        QuickChip(label: "💵 Net Kar Marjı",    query: "Net kar marjı nedir ve sektörler arası nasıl karşılaştırılır?", category: "📋 Temel Analiz"),
        QuickChip(label: "⚖️ Borç/Özsermaye",  query: "Borç/Özsermaye oranı nedir, yüksek olması ne anlama gelir?",category: "📋 Temel Analiz"),
        QuickChip(label: "💧 Cari Oran",        query: "Cari oran nedir ve şirket sağlığını nasıl gösterir?",       category: "📋 Temel Analiz"),
        QuickChip(label: "📈 Gelir Büyümesi",   query: "Şirket gelir büyümesi nasıl analiz edilir?",                category: "📋 Temel Analiz"),
        QuickChip(label: "🏭 Sektör Analizi",   query: "Sektör bazlı temel analiz nasıl yapılır?",                  category: "📋 Temel Analiz"),
        QuickChip(label: "📋 Bilanço Okuma",    query: "Bilanço nasıl okunur ve ne anlama gelir?",                  category: "📋 Temel Analiz"),
        QuickChip(label: "📑 Gelir Tablosu",    query: "Gelir tablosu nedir ve nasıl yorumlanır?",                  category: "📋 Temel Analiz"),
        QuickChip(label: "🔢 Nakit Akışı",      query: "Nakit akışı analizi nedir?",                                category: "📋 Temel Analiz"),

        // ── Piyasa & Kavramlar ──
        QuickChip(label: "📊 Piyasa Özeti",     query: "Genel piyasa durumunu anlat.",                              category: "🏛️ Piyasa & Kavramlar"),
        QuickChip(label: "🏆 BIST 100",         query: "BIST 100 endeksi nedir ve nasıl hesaplanır?",               category: "🏛️ Piyasa & Kavramlar"),
        QuickChip(label: "📋 BIST 30 / 50",     query: "BIST 30 ve BIST 50 endeksleri nedir?",                     category: "🏛️ Piyasa & Kavramlar"),
        QuickChip(label: "🎲 Lot nedir?",       query: "Borsada lot nedir, kaç hisse 1 lottur?",                   category: "🏛️ Piyasa & Kavramlar"),
        QuickChip(label: "🎉 Halka Arz (IPO)",  query: "Halka arz (IPO) nedir, nasıl katılınır?",                  category: "🏛️ Piyasa & Kavramlar"),
        QuickChip(label: "💱 Döviz Etkisi",     query: "Döviz kurlarının hisse senetlerine etkisi nedir?",          category: "🏛️ Piyasa & Kavramlar"),
        QuickChip(label: "📊 Enflasyon Etkisi", query: "Enflasyonun hisse senetlerine etkisi nasıldır?",            category: "🏛️ Piyasa & Kavramlar"),
        QuickChip(label: "🏦 Faiz Etkisi",      query: "Merkez Bankası faiz kararlarının borsaya etkisi nedir?",   category: "🏛️ Piyasa & Kavramlar"),
        QuickChip(label: "🌍 Küresel Piyasalar",query: "ABD borsalarının BIST üzerindeki etkisi nedir?",            category: "🏛️ Piyasa & Kavramlar"),
        QuickChip(label: "📜 Hisse Senedi",     query: "Hisse senedi nedir, nasıl çalışır?",                       category: "🏛️ Piyasa & Kavramlar"),
        QuickChip(label: "🔄 Piyasa Saatleri",  query: "BIST'in işlem saatleri nedir?",                            category: "🏛️ Piyasa & Kavramlar"),
        QuickChip(label: "⛔ Devre Kesici",     query: "Devre kesici (circuit breaker) nedir?",                    category: "🏛️ Piyasa & Kavramlar"),
        QuickChip(label: "📰 Haberler Etkisi",  query: "Şirket haberleri hisse fiyatını nasıl etkiler?",           category: "🏛️ Piyasa & Kavramlar"),

        // ── Strateji & Eğitim ──
        QuickChip(label: "🛑 Stop-Loss",        query: "Stop-loss nedir ve nasıl kullanılır?",                      category: "🎯 Strateji & Eğitim"),
        QuickChip(label: "🎯 Risk/Getiri",      query: "Risk/Getiri oranı nedir ve nasıl hesaplanır?",              category: "🎯 Strateji & Eğitim"),
        QuickChip(label: "🌐 Çeşitlendirme",    query: "Portföy çeşitlendirmesi nedir, neden önemlidir?",           category: "🎯 Strateji & Eğitim"),
        QuickChip(label: "⬆️ Long Pozisyon",    query: "Uzun pozisyon (long) nedir?",                              category: "🎯 Strateji & Eğitim"),
        QuickChip(label: "⬇️ Açığa Satış",      query: "Açığa satış (short selling) nedir ve nasıl çalışır?",     category: "🎯 Strateji & Eğitim"),
        QuickChip(label: "🔄 DCA Stratejisi",   query: "Dollar-cost averaging (DCA) stratejisi nedir?",             category: "🎯 Strateji & Eğitim"),
        QuickChip(label: "📊 Teknik mi Temel?", query: "Teknik analiz mi temel analiz mi daha etkilidir?",          category: "🎯 Strateji & Eğitim"),
        QuickChip(label: "⚠️ Piyasa Riski",    query: "Piyasa riski türleri nelerdir?",                            category: "🎯 Strateji & Eğitim"),
        QuickChip(label: "🧮 Pozisyon Boyutu",  query: "Pozisyon boyutu nasıl belirlenir?",                         category: "🎯 Strateji & Eğitim"),
        QuickChip(label: "🔁 Trailing Stop",    query: "Trailing stop nedir ve stop-loss'tan farkı nedir?",         category: "🎯 Strateji & Eğitim"),
        QuickChip(label: "💡 Momentum Ticaret", query: "Momentum trading stratejisi nedir?",                        category: "🎯 Strateji & Eğitim"),
        QuickChip(label: "🧘 Swing Trading",    query: "Swing trading nedir ve gün içi işlemden farkı nedir?",      category: "🎯 Strateji & Eğitim"),
    ]

    static var categories: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for chip in defaults {
            if seen.insert(chip.category).inserted {
                ordered.append(chip.category)
            }
        }
        return ordered
    }

    static func chips(for category: String) -> [QuickChip] {
        defaults.filter { $0.category == category }
    }
}
