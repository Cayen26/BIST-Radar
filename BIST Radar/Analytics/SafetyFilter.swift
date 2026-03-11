// SafetyFilter.swift – Blocks advice, enforces educational tone
// BIST Radar AI
// All assistant outputs MUST pass through this filter.

import Foundation

final class SafetyFilter: Sendable {

    // MARK: - Forbidden phrases (Turkish + English)
    private let forbiddenPhrases: [(pattern: String, replacement: String)] = [
        // Buy signals
        ("al[ı]n[ı]z", "ilgilenebilirsiniz (eğitsel)"),
        ("satın al", "[eğitsel değerlendirme]"),
        ("buy", "[eğitsel değerlendirme]"),
        ("alım fırsatı", "teknik görünüm"),
        ("alım sinyali", "teknik gösterge"),
        // Sell signals
        ("sat[ı]n[ı]z", "[eğitsel değerlendirme]"),
        ("sat[ı]şı değerlendirin", "[eğitsel değerlendirme]"),
        ("sell", "[eğitsel değerlendirme]"),
        ("satım sinyali", "teknik gösterge"),
        // Recommendations
        ("öneri", "eğitsel bilgi"),
        ("öneririm", "eğitsel açıdan belirtiyorum"),
        ("tavsiye ederim", "eğitsel açıdan belirtiyorum"),
        ("recommend", "educationally note"),
        ("I suggest", "educationally note"),
        // Target prices
        ("hedef fiyat", "teknik seviye"),
        ("target price", "technical level"),
        ("fiyat hedefi", "teknik seviye"),
        // Guarantees
        ("garantili", "istatistiksel"),
        ("kesin", "olası"),
        ("emin ol", "dikkate al"),
        ("guaranteed", "statistically"),
        ("sure profit", "historical pattern"),
        ("kesin kâr", "istatistiksel örüntü"),
        ("kesinlikle", "büyük olasılıkla"),
        // Pump/hype
        ("hisse fırlayacak", "hisse değişim gösterdi"),
        ("patlama yapacak", "yüksek volatilite var"),
        ("çok kazandırır", "tarihsel veriler gösteriyor"),
    ]

    private let requiredDisclaimer = "Bu bir yatırım tavsiyesi değildir."

    // MARK: - Main filter function
    func filter(_ input: String) -> String {
        var result = input

        // 1. Replace forbidden phrases
        for (pattern, replacement) in forbiddenPhrases {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(result.startIndex..., in: result)
                result = regex.stringByReplacingMatches(
                    in: result, range: range,
                    withTemplate: replacement
                )
            }
        }

        // 2. Ensure disclaimer at end
        if !result.contains(requiredDisclaimer) {
            result += "\n\n\(requiredDisclaimer)"
        }

        return result
    }

    // MARK: - Validate (returns issues found)
    func validate(_ input: String) -> [String] {
        var issues: [String] = []
        let lower = input.lowercased()

        for (pattern, _) in forbiddenPhrases {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(lower.startIndex..., in: lower)
                if regex.firstMatch(in: lower, range: range) != nil {
                    issues.append("Yasaklı ifade tespit edildi: '\(pattern)'")
                }
            }
        }

        if !input.contains(requiredDisclaimer) {
            issues.append("Yasal uyarı eksik: '\(requiredDisclaimer)'")
        }

        return issues
    }

    // MARK: - Block check
    func isBlocked(_ input: String) -> Bool {
        !validate(input).isEmpty
    }
}
