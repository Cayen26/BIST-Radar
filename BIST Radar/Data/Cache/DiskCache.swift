// DiskCache.swift – FileManager-based JSON disk cache with TTL
// BIST Radar AI

import Foundation
import Combine

actor DiskCache {
    static let shared = DiskCache()

    private let fm = FileManager.default
    private let cacheDir: URL

    private init() {
        let dir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = dir.appendingPathComponent("BISTRadar", isDirectory: true)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Write
    func write<T: Encodable>(_ value: T, key: String, ttl: TimeInterval) async {
        let wrapper = EncodableCacheWrapper(value: value, expiresAt: Date().addingTimeInterval(ttl))
        guard let data = try? JSONEncoder().encode(wrapper) else { return }
        let url = fileURL(key: key)
        try? data.write(to: url, options: [.atomic])
    }

    // MARK: - Read
    func read<T: Decodable>(key: String, as type: T.Type) async -> T? {
        let url = fileURL(key: key)
        guard let data = try? Data(contentsOf: url),
              let wrapper = try? JSONDecoder().decode(DecodableCacheWrapper<T>.self, from: data) else {
            return nil
        }
        if wrapper.isExpired {
            try? fm.removeItem(at: url)
            return nil
        }
        return wrapper.value
    }

    // MARK: - Clear
    func remove(key: String) async {
        try? fm.removeItem(at: fileURL(key: key))
    }

    func clearAll() async {
        try? fm.removeItem(at: cacheDir)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Helpers
    private func fileURL(key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
                      .replacingOccurrences(of: ":", with: "_")
        return cacheDir.appendingPathComponent("\(safe).json")
    }
}

// MARK: - Wrappers
private struct EncodableCacheWrapper<T: Encodable>: Encodable {
    let value: T
    let expiresAt: Date

    var isExpired: Bool { Date() > expiresAt }
}

private struct DecodableCacheWrapper<T: Decodable>: Decodable {
    let value: T
    let expiresAt: Date

    var isExpired: Bool { Date() > expiresAt }
}
