// SkeletonView.swift – Skeleton loading state components
// BIST Radar AI

import SwiftUI

// MARK: - Base skeleton modifier
struct SkeletonModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.surface3,
                            Color.surface4.opacity(0.8),
                            Color.surface3,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: geo.size.width * phase)
                    .animation(
                        .linear(duration: 1.4).repeatForever(autoreverses: false),
                        value: phase
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
            )
            .onAppear { phase = 1 }
    }
}

extension View {
    func skeleton() -> some View {
        modifier(SkeletonModifier())
    }
}

// MARK: - Stock Row Skeleton
struct StockRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.surface3)
                .frame(width: 44, height: 44)
                .skeleton()

            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.surface3)
                    .frame(width: 80, height: 14)
                    .skeleton()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.surface3)
                    .frame(width: 130, height: 12)
                    .skeleton()
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.surface3)
                    .frame(width: 60, height: 14)
                    .skeleton()
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.surface3)
                    .frame(width: 50, height: 12)
                    .skeleton()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Chart Skeleton
struct ChartSkeleton: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.surface2)
            .frame(height: 200)
            .skeleton()
    }
}

// MARK: - Card Skeleton
struct CardSkeleton: View {
    var height: CGFloat = 80

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.surface2)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .skeleton()
    }
}
