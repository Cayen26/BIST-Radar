// InsightCardView.swift – Displays a single educational insight
// BIST Radar AI

import SwiftUI

struct InsightCardView: View {
    let insight: Insight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: insight.category.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(insight.severity.color)
                Text(insight.title)
                    .font(.caption.bold())
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                if !insight.numericEvidence.isEmpty {
                    Text(insight.numericEvidence)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                        .lineLimit(1)
                }
            }

            Text(insight.body)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.surface2)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(insight.severity.color.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Full Insights Section
struct InsightsSectionView: View {
    let insights: [Insight]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Eğitsel Analiz", icon: "brain")

            if isLoading {
                ForEach(0..<3, id: \.self) { _ in
                    CardSkeleton(height: 80)
                }
            } else if insights.isEmpty {
                Text("Analiz için yeterli veri yok.")
                    .font(.caption)
                    .foregroundStyle(Color.textTertiary)
                    .padding()
            } else {
                ForEach(insights) { insight in
                    InsightCardView(insight: insight)
                }

                // Mandatory disclaimer at bottom of insights
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                        .font(.caption2)
                    Text("Bu bir yatırım tavsiyesi değildir.")
                        .font(.caption2)
                }
                .foregroundStyle(Color.textTertiary)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    let icon: String
    var iconColor: Color = .brandAccent
    var trailing: String? = nil

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption.bold())
                .foregroundStyle(iconColor)
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.caption)
                    .foregroundStyle(Color.brandAccent)
            }
        }
    }
}

// MARK: - Disclaimer Banner (for assistant + settings)
struct DisclaimerBannerView: View {
    var showFull: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .foregroundStyle(Color.negative)
                .font(.callout)
            Text(showFull ? DisclaimerText.full : DisclaimerText.short)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color.negative.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.negative.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Extensions for Insight display
extension InsightCategory {
    var iconName: String {
        switch self {
        case .performance: return "chart.line.uptrend.xyaxis"
        case .momentum:    return "gauge.high"
        case .volume:      return "waveform.path.ecg"
        case .volatility:  return "bolt.fill"
        case .movingAvg:   return "chart.line.flattrend.xyaxis"
        case .unusual:     return "exclamationmark.triangle.fill"
        case .general:     return "info.circle"
        }
    }
}

extension InsightSeverity {
    var color: Color {
        switch self {
        case .info:    return Color.brandAccent
        case .warning: return Color(hex: "#F59E0B")
        case .neutral: return Color.textSecondary
        }
    }
}
