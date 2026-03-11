// OnboardingView.swift – First-launch with mandatory disclaimer
// BIST Radar AI

import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "chart.xyaxis.line",
            title: "BIST Radar AI",
            subtitle: "Tüm BIST evrenini tek uygulamada keşfedin",
            body: "200'den fazla BIST şirketi için gerçek zamanlı veriler, teknik göstergeler ve eğitsel analizler."
        ),
        OnboardingPage(
            icon: "brain.head.profile",
            title: "AI Asistanı",
            subtitle: "Piyasayı anlayın, soru sorun",
            body: "Hisse verileri hakkında sorular sorun. Asistan RSI, hacim, hareketli ortalama gibi kavramları Türkçe açıklar."
        ),
        OnboardingPage(
            icon: "shield.checkered",
            title: "Yasal Uyarı",
            subtitle: "Önemli: Bu uygulama yatırım tavsiyesi vermez",
            body: DisclaimerText.full,
            isDisclaimer: true
        ),
    ]

    var body: some View {
        ZStack {
            Color.surface1.ignoresSafeArea()

            // Ambient top glow
            VStack {
                RadialGradient(
                    colors: [Color.brandAccent.opacity(0.10), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 220
                )
                .frame(width: 440, height: 440)
                .offset(y: -80)
                .blur(radius: 20)
                Spacer()
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                        OnboardingPageView(page: page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Capsule page indicators
                HStack(spacing: 6) {
                    ForEach(0..<pages.count, id: \.self) { idx in
                        Capsule()
                            .fill(idx == currentPage ? Color.brandAccent : Color.surface4)
                            .frame(width: idx == currentPage ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: currentPage)
                    }
                }
                .padding(.bottom, 28)

                // CTA button
                Button(action: handleCTA) {
                    HStack(spacing: 8) {
                        Text(currentPage == pages.count - 1 ? "Kabul Ediyorum, Başla" : "Devam")
                            .font(.body.weight(.semibold))
                        Image(systemName: currentPage == pages.count - 1 ? "checkmark" : "arrow.right")
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(
                        LinearGradient(
                            colors: [Color.brandAccent, Color(hex: "#0099CC")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: Color.brandAccent.opacity(0.38), radius: 18, x: 0, y: 7)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
    }

    private func handleCTA() {
        if currentPage < pages.count - 1 {
            withAnimation(.easeInOut(duration: 0.25)) { currentPage += 1 }
        } else {
            hasSeenOnboarding = true
        }
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let subtitle: String
    let body: String
    var isDisclaimer: Bool = false
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var glowing = false

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer(minLength: 44)

                // Animated icon with glow
                ZStack {
                    Circle()
                        .fill(Color.brandAccent.opacity(glowing ? 0.14 : 0.05))
                        .frame(width: 160, height: 160)
                        .blur(radius: 24)
                        .scaleEffect(glowing ? 1.2 : 1.0)
                        .animation(
                            .easeInOut(duration: 2.4).repeatForever(autoreverses: true),
                            value: glowing
                        )

                    RoundedRectangle(cornerRadius: 28)
                        .fill(Color.surface3)
                        .frame(width: 100, height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28)
                                .stroke(Color.brandAccent.opacity(0.22), lineWidth: 1)
                        )

                    Image(systemName: page.icon)
                        .font(.system(size: 46, weight: .thin))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.brandAccent, Color.brandAccent.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(.bottom, 36)
                .onAppear { glowing = true }

                // Text
                VStack(spacing: 10) {
                    Text(page.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(Color.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(page.subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.brandAccent)
                        .multilineTextAlignment(.center)
                }
                .padding(.bottom, 24)

                if page.isDisclaimer {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 7) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(Color.negative)
                            Text("Yasal Uyarı")
                                .font(.caption.bold())
                                .foregroundStyle(Color.negative)
                        }
                        Text(page.body)
                            .font(.footnote)
                            .foregroundStyle(Color.textSecondary)
                            .lineSpacing(3)
                    }
                    .padding(16)
                    .background(Color.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.negative.opacity(0.35), lineWidth: 1)
                    )
                } else {
                    Text(page.body)
                        .font(.body)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 28)
        }
    }
}

// MARK: - Disclaimer text (shared)
enum DisclaimerText {
    static let short = "Bu uygulama yatırım tavsiyesi vermez. Veriler yalnızca eğitsel amaçlıdır."

    static let full = """
    Bu uygulama ve içerikleri yalnızca eğitsel ve bilgilendirme amaçlıdır.

    • Uygulama hiçbir şekilde yatırım tavsiyesi vermemektedir.
    • "Al", "sat", "hedef fiyat", "kesin kâr" gibi ifadeler kullanılmaz.
    • Gösterilen veriler gecikmiş olabilir; gerçek zamanlı işlemler için aracı kurumunuzu kullanın.
    • Piyasalarda zarar riski her zaman mevcuttur.
    • Yatırım kararları almadan önce lisanslı bir finansal danışmana başvurunuz.
    • Geçmiş performans gelecekteki sonuçları garanti etmez.

    Kullanmaya devam ederek bu koşulları kabul etmiş sayılırsınız.
    """
}
