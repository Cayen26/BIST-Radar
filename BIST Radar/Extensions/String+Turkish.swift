// String+Turkish.swift – Turkish character normalization for fast search
// BIST Radar AI

import Foundation

extension String {

    /// Returns a lowercase, ASCII-normalized string for Turkish-safe search.
    /// Maps: İ→i, I→ı→i, Ş→ş→s, Ğ→ğ→g, Ü→ü→u, Ö→ö→o, Ç→ç→c
    func turkishNormalized() -> String {
        var result = self.lowercased()
        let map: [(String, String)] = [
            ("İ", "i"), ("ı", "i"),
            ("Ş", "s"), ("ş", "s"),
            ("Ğ", "g"), ("ğ", "g"),
            ("Ü", "u"), ("ü", "u"),
            ("Ö", "o"), ("ö", "o"),
            ("Ç", "c"), ("ç", "c"),
            ("I", "i"),
        ]
        for (from, to) in map {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    /// Returns true if the normalized string contains the given normalized query.
    func turkishContains(_ query: String) -> Bool {
        self.turkishNormalized().contains(query.turkishNormalized())
    }

    /// Formats as a percentage string with sign.
    static func percentFormatted(_ value: Double, digits: Int = 2) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(String(format: "%.\(digits)f", value))%"
    }
}
