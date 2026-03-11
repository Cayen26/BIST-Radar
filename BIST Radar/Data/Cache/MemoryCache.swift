// MemoryCache.swift – Thread-safe NSCache wrapper with TTL
// BIST Radar AI

import Foundation

final class MemoryCacheEntry<T>: NSObject {
    let value: T
    let expiresAt: Date

    init(value: T, ttl: TimeInterval) {
        self.value = value
        self.expiresAt = Date().addingTimeInterval(ttl)
    }

    var isExpired: Bool { Date() > expiresAt }
}

final class MemoryCache<Key: Hashable, Value>: @unchecked Sendable {
    private let cache = NSCache<AnyObject, MemoryCacheEntry<Value>>()
    private let lock  = NSLock()

    init(maxCount: Int = 500) {
        cache.countLimit = maxCount
    }

    func set(_ value: Value, forKey key: Key, ttl: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        let entry = MemoryCacheEntry(value: value, ttl: ttl)
        cache.setObject(entry, forKey: key as AnyObject)
    }

    func value(forKey key: Key) -> Value? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = cache.object(forKey: key as AnyObject) else { return nil }
        if entry.isExpired {
            cache.removeObject(forKey: key as AnyObject)
            return nil
        }
        return entry.value
    }

    func removeValue(forKey key: Key) {
        lock.lock(); defer { lock.unlock() }
        cache.removeObject(forKey: key as AnyObject)
    }

    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        cache.removeAllObjects()
    }
}

// MARK: - Shared caches
enum AppCaches {
    static let quotes    = MemoryCache<String, Quote>(maxCount: 600)
    static let candles   = MemoryCache<String, [Candle]>(maxCount: 100)
    static let fundas    = MemoryCache<String, Fundamentals>(maxCount: 200)
    static let sectors   = MemoryCache<String, [Sector]>(maxCount: 1)
    static let indices   = MemoryCache<String, [BISTIndex]>(maxCount: 1)
    static let news      = MemoryCache<String, [NewsArticle]>(maxCount: 10)
    static let newsTTL: TimeInterval = 5 * 60  // 5 min

    // TTLs (seconds)
    static let quoteTTL: TimeInterval    = 30        // 30 sn – fiyat sık değişir
    static let candleTTL: TimeInterval   = 60        // 1 dk – varsayılan (intraday için geçerli)
    static let fundaTTL: TimeInterval    = 24 * 3600 // 24 h
    static let sectorTTL: TimeInterval   = 5 * 60    // 5 min

    /// Mum timeframe'e göre cache süresi: intraday kısa, uzun vadeli daha uzun
    static func candleTTL(for timeframe: CandleTimeframe) -> TimeInterval {
        switch timeframe {
        case .oneDay:      return 60        // 1 dk – 5dk'lık intraday mumlar
        case .oneWeek:     return 3 * 60    // 3 dk
        case .oneMonth:    return 5 * 60    // 5 dk
        case .threeMonths: return 10 * 60   // 10 dk
        case .oneYear:     return 15 * 60   // 15 dk
        }
    }
}
