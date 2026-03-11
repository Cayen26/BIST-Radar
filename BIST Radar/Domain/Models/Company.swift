// Company.swift – Universe record (SwiftData model)
// BIST Radar AI

import Foundation
import SwiftData

@Model
final class Company {
    // MARK: - Core Identity
    @Attribute(.unique) var symbol: String
    var companyNameTr: String
    var shortName: String
    var sector: String
    var subSector: String
    var marketSegment: String      // "Yıldız", "Ana", "Alt"
    var isActive: Bool

    // MARK: - Index Membership
    var inBIST30: Bool
    var inBIST50: Bool
    var inBIST100: Bool

    // MARK: - Normalized search fields (Turkish-safe)
    var symbolNorm: String          // uppercase ASCII-normalized
    var nameNorm: String            // lowercase ASCII-normalized

    // MARK: - Meta
    var updatedAt: Date

    init(
        symbol: String,
        companyNameTr: String,
        shortName: String,
        sector: String,
        subSector: String = "",
        marketSegment: String,
        isActive: Bool = true,
        inBIST30: Bool = false,
        inBIST50: Bool = false,
        inBIST100: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.symbol = symbol
        self.companyNameTr = companyNameTr
        self.shortName = shortName
        self.sector = sector
        self.subSector = subSector
        self.marketSegment = marketSegment
        self.isActive = isActive
        self.inBIST30 = inBIST30
        self.inBIST50 = inBIST50
        self.inBIST100 = inBIST100
        self.updatedAt = updatedAt
        self.symbolNorm = symbol.turkishNormalized()
        self.nameNorm = companyNameTr.turkishNormalized()
    }
}

// MARK: - DTO (decoding from API / JSON)
struct CompanyDTO: Codable, Sendable {
    let symbol: String
    let companyNameTr: String
    let shortName: String
    let sector: String
    let subSector: String?
    let marketSegment: String
    let isActive: Bool
    let indexFlags: IndexFlags
    let updatedAt: Date?

    struct IndexFlags: Codable, Sendable {
        let bist30: Bool
        let bist50: Bool
        let bist100: Bool
    }

    func toModel() -> Company {
        Company(
            symbol: symbol,
            companyNameTr: companyNameTr,
            shortName: shortName,
            sector: sector,
            subSector: subSector ?? "",
            marketSegment: marketSegment,
            isActive: isActive,
            inBIST30: indexFlags.bist30,
            inBIST50: indexFlags.bist50,
            inBIST100: indexFlags.bist100,
            updatedAt: updatedAt ?? Date()
        )
    }
}
