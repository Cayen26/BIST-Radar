// StockRowView.swift – Stock list row component
// BIST Radar AI

import SwiftUI

struct StockRowView: View {
    let company: Company
    let quote: Quote?
    let isInWatchlist: Bool
    var onTap: (() -> Void)? = nil
    var onWatchlistToggle: (() -> Void)? = nil

    private var isPos: Bool { (quote?.changePercent ?? 0) >= 0 }
    private var accentColor: Color {
        guard let q = quote else { return Color.surface3 }
        return q.isPositive ? Color.positive : Color.negative
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left trend accent bar (visible only when data loaded)
            Rectangle()
                .fill(quote != nil ? accentColor.opacity(0.6) : Color.clear)
                .frame(width: 3)

            HStack(spacing: 12) {
                // Symbol badge
                SymbolBadge(symbol: company.symbol, sector: company.sector)

                // Company info
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(company.symbol)
                            .font(.system(.callout, design: .monospaced, weight: .bold))
                            .foregroundStyle(Color.textPrimary)
                        if company.inBIST30 {
                            IndexBadge(label: "30")
                        } else if company.inBIST50 {
                            IndexBadge(label: "50")
                        } else if company.inBIST100 {
                            IndexBadge(label: "100")
                        }
                    }
                    Text(company.shortName)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Price info
                if let q = quote {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(q.formattedPrice)
                            .font(.system(.callout, design: .monospaced, weight: .semibold))
                            .foregroundStyle(Color.textPrimary)
                        let sign = q.isPositive ? "+" : ""
                        HStack(spacing: 2) {
                            Image(systemName: q.isPositive ? "arrow.up" : "arrow.down")
                                .font(.system(size: 8, weight: .bold))
                            Text("\(sign)\(String(format: "%.2f", q.changePercent))%")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(q.isPositive ? Color.positive : Color.negative)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background((q.isPositive ? Color.positive : Color.negative).opacity(0.13))
                        .clipShape(Capsule())
                    }
                } else {
                    VStack(alignment: .trailing, spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.surface3)
                            .frame(width: 64, height: 14)
                            .skeleton()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.surface3)
                            .frame(width: 48, height: 12)
                            .skeleton()
                    }
                }

                // Watchlist button
                if let toggle = onWatchlistToggle {
                    Button(action: toggle) {
                        Image(systemName: isInWatchlist ? "star.fill" : "star")
                            .font(.system(size: 16))
                            .foregroundStyle(isInWatchlist ? Color.brandAccent : Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
        }
        .background(Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onTap?() }
    }
}

// MARK: - Symbol Badge
struct SymbolBadge: View {
    let symbol: String
    let sector: String

    private var color: Color { Color.sectorColor(for: sector) }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.16))
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(color.opacity(0.25), lineWidth: 1)
                )
            Text(symbol.prefix(3))
                .font(.system(size: 11, weight: .black, design: .monospaced))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Index badge
struct IndexBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Color.brandAccent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.brandAccent.opacity(0.15))
            .clipShape(Capsule())
    }
}

// MARK: - Change badge (reusable)
struct ChangeBadge: View {
    let value: Double
    var suffix: String = "%"

    var isPositive: Bool { value >= 0 }

    var body: some View {
        let sign = isPositive ? "+" : ""
        HStack(spacing: 2) {
            Image(systemName: isPositive ? "arrow.up" : "arrow.down")
                .font(.system(size: 8, weight: .bold))
            Text("\(sign)\(String(format: "%.2f", value))\(suffix)")
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundStyle(isPositive ? Color.positive : Color.negative)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background((isPositive ? Color.positive : Color.negative).opacity(0.13))
        .clipShape(Capsule())
    }
}
