// AlertRule.swift – Smart alert definitions (SwiftData)
// BIST Radar AI

import Foundation
import SwiftData

enum AlertTriggerType: String, Codable, CaseIterable {
    case priceAbove       = "Fiyat Üstünde"
    case priceBelow       = "Fiyat Altında"
    case changePctAbove   = "Günlük Değişim Üstünde"
    case changePctBelow   = "Günlük Değişim Altında"
    case rsiAbove         = "RSI Üstünde"
    case rsiBelow         = "RSI Altında"
    case volumeSpikeAbove = "Hacim Artışı Üstünde"
}

@Model
final class AlertRule {
    var id: UUID
    var symbol: String
    var companyNameTr: String
    var triggerType: String      // AlertTriggerType.rawValue
    var thresholdValue: Double
    var isActive: Bool
    var createdAt: Date
    var lastTriggeredAt: Date?

    init(
        symbol: String,
        companyNameTr: String,
        triggerType: AlertTriggerType,
        thresholdValue: Double
    ) {
        self.id = UUID()
        self.symbol = symbol
        self.companyNameTr = companyNameTr
        self.triggerType = triggerType.rawValue
        self.thresholdValue = thresholdValue
        self.isActive = true
        self.createdAt = Date()
    }

    var triggerTypeEnum: AlertTriggerType? {
        AlertTriggerType(rawValue: triggerType)
    }

    var descriptionTR: String {
        guard let type = triggerTypeEnum else { return triggerType }
        switch type {
        case .priceAbove:
            return "\(symbol) fiyatı \(String(format: "%.2f", thresholdValue)) ₺ üzerine çıktığında"
        case .priceBelow:
            return "\(symbol) fiyatı \(String(format: "%.2f", thresholdValue)) ₺ altına düştüğünde"
        case .changePctAbove:
            return "\(symbol) günlük değişimi %\(String(format: "%.1f", thresholdValue)) üzerinde olduğunda"
        case .changePctBelow:
            return "\(symbol) günlük değişimi %-\(String(format: "%.1f", abs(thresholdValue))) altında olduğunda"
        case .rsiAbove:
            return "\(symbol) RSI(14) \(String(format: "%.0f", thresholdValue)) üzerine çıktığında"
        case .rsiBelow:
            return "\(symbol) RSI(14) \(String(format: "%.0f", thresholdValue)) altına düştüğünde"
        case .volumeSpikeAbove:
            return "\(symbol) hacmi 20 günlük ortalamanın %\(String(format: "%.0f", thresholdValue)) üzerinde olduğunda"
        }
    }
}
