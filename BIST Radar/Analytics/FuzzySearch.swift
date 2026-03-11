// FuzzySearch.swift – Merkezi fuzzy arama (tüm uygulama)
// BIST Radar AI

import Foundation

enum FuzzySearch {

    // MARK: - Liste araması (arama kutusu — kullanıcı doğrudan sembol/ad yazar)

    static func filter(_ companies: [Company], query: String) -> [Company] {
        let q = query.turkishNormalized().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return companies }

        // 1. Tam sembol eşleme
        let exact = companies.filter { $0.symbolNorm == q }
        if !exact.isEmpty { return exact }

        // 2. Substring (sembol veya ad içeriyor) — arama kutusunda yeterli
        let substring = companies.filter {
            $0.symbolNorm.contains(q) || $0.nameNorm.contains(q)
        }
        if !substring.isEmpty { return substring }

        let words = q.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 }

        // 3. Sembol prefix
        let symPrefix = companies.filter { c in words.contains { c.symbolNorm.hasPrefix($0) } }
        if !symPrefix.isEmpty { return symPrefix }

        // 4. Ad kelime prefix ("arcel" → "arcelik")
        let namePrefix = companies.filter { c in
            let nw = c.nameNorm.components(separatedBy: " ")
            return words.contains { w in w.count >= 3 && nw.contains { $0.hasPrefix(w) } }
        }
        if !namePrefix.isEmpty { return namePrefix }

        // 5. Edit distance ≤ 1 (sembol veya ad kelimesi)
        let fuzzy = companies.filter { c in
            words.contains { w in
                guard w.count >= 4 else { return false }
                let thr = w.count <= 5 ? 1 : 2
                if editDistance(w, c.symbolNorm) <= thr { return true }
                return c.nameNorm.components(separatedBy: " ")
                    .contains { $0.count >= 3 && editDistance(w, $0) <= thr }
            }
        }
        if !fuzzy.isEmpty { return fuzzy }

        // 6. Subsequence
        return companies.filter { c in
            words.contains { w in
                w.count >= 3 &&
                isSubsequence(w, of: c.symbolNorm) &&
                c.symbolNorm.count - w.count <= 2
            }
        }
    }

    // MARK: - Asistan sembol çözümleme (doğal dil cümlesi)
    //
    // ÖNEMLİ: shortName/ad eşlemesi KELIME BAZLI yapılır — cümle substring'i değil.
    // "asels destek direnç" → "asels" kelimesi → ASELS (ASELSAN) ✓
    // "asels destek direnç" → "sel" substring eşleme YOK → SKTF hatası önlenir ✓

    struct ResolveEntry {
        let symbol: String
        let symbolNorm: String
        let nameNorm: String
        let shortNameNorm: String
    }

    static func resolve(query: String, catalog: [ResolveEntry], stopWords: Set<String>) -> String? {
        let qNorm = query.turkishNormalized()

        // Sorguyu kelimelerine ayır, stop word'leri çıkar
        let queryWords = qNorm
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 && !stopWords.contains($0) }
            .sorted { $0.count > $1.count }   // uzun kelimeler önce

        guard !catalog.isEmpty, !queryWords.isEmpty else { return nil }

        // Puanlama: her şirket için en yüksek eşleme puanını hesapla
        // Yüksek puan = daha kesin eşleme
        var bestSymbol: String? = nil
        var bestScore  = 0

        for entry in catalog {
            var score = 0
            let nameWords = entry.nameNorm.components(separatedBy: " ")

            for word in queryWords {
                // 100 — Tam sembol eşleme ("asels" == "asels")
                if entry.symbolNorm == word {
                    score = max(score, 100); break
                }

                // 95 — ShortName tam kelime eşleme ("thy" kelimesi == shortName "thy")
                if entry.shortNameNorm.count >= 3, word == entry.shortNameNorm {
                    score = max(score, 95)
                }

                // 90 — Sembol prefix ("gar" → "garan", "asels" → "asels")
                if word.count >= 2,
                   entry.symbolNorm.hasPrefix(word),
                   entry.symbolNorm.count - word.count <= 2 {
                    score = max(score, 90)
                }

                // 80 — Ad kelime tam eşleme ("netcad" ∈ nameWords)
                if word.count >= 4, nameWords.contains(word) {
                    score = max(score, 80)
                }

                // 70 — Ad kelime prefix ("arcel" → "arcelik")
                if word.count >= 4,
                   nameWords.contains(where: { $0.hasPrefix(word) && $0.count - word.count <= 3 }) {
                    score = max(score, 70)
                }

                // 60 — Ad kelime fuzzy edit dist ≤ 1 ("tupras" → "tuprs")
                if word.count >= 4 {
                    if nameWords.contains(where: { $0.count >= 3 && editDistance(word, $0) <= 1 }) {
                        score = max(score, 60)
                    }
                }

                // 50 — Sembol edit distance ≤ 1 ("netcd" → "netcad")
                if word.count >= 4 {
                    let thr = word.count <= 5 ? 1 : 2
                    if editDistance(word, entry.symbolNorm) <= thr {
                        score = max(score, 50)
                    }
                }

                // 35 — Subsequence ("ntcd" ⊂ "netcad")
                if word.count >= 3,
                   isSubsequence(word, of: entry.symbolNorm),
                   entry.symbolNorm.count - word.count <= 2 {
                    score = max(score, 35)
                }
            }

            if score > bestScore {
                bestScore = score
                bestSymbol = entry.symbol
            }
        }

        // Minimum eşik: sadece anlamlı eşleme döndür (false positive önler)
        return bestScore >= 50 ? bestSymbol : nil
    }

    // MARK: - Yardımcı: Levenshtein edit distance

    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        let m = a.count, n = b.count
        if m == 0 { return n }
        if n == 0 { return m }
        var row = Array(0...n)
        for i in 1...m {
            var prev = row[0]
            row[0] = i
            for j in 1...n {
                let temp = row[j]
                row[j] = a[i-1] == b[j-1] ? prev : min(prev, min(row[j], row[j-1])) + 1
                prev = temp
            }
        }
        return row[n]
    }

    // MARK: - Yardımcı: Subsequence kontrolü

    static func isSubsequence(_ word: String, of target: String) -> Bool {
        var it = word.makeIterator()
        guard var next = it.next() else { return true }
        for ch in target {
            if ch == next {
                guard let n = it.next() else { return true }
                next = n
            }
        }
        return false
    }
}
