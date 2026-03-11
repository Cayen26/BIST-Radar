// SettingsView.swift – App settings with disclaimers
// BIST Radar AI

import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var appContainer: AppContainer
    @Environment(\.modelContext) private var modelContext

    // User preferences
    @AppStorage("preferredColorScheme") private var colorScheme = "dark"
    @AppStorage("isAIEnabled") private var isAIEnabled = true
    @AppStorage("quoteTTLSeconds") private var quoteTTL = 60.0
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true
    @AppStorage("liveNewsEnabled") private var liveNewsEnabled = true

    @State private var showFullDisclaimer = false
    @State private var showClearCacheAlert = false
    @State private var showResetOnboarding = false
    @State private var isRefreshingUniverse = false
    @State private var showTerms = false
    @State private var showPrivacy = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface1.ignoresSafeArea()

                Form {
                    // Disclaimer (always visible)
                    Section {
                        DisclaimerBannerView(showFull: false)
                            .listRowBackground(Color.clear)
                        Button("Tam Yasal Uyarıyı Görüntüle") {
                            showFullDisclaimer = true
                        }
                        .font(.footnote)
                        .foregroundStyle(Color.brandAccent)
                        .listRowBackground(Color.surface2)
                    } header: {
                        Text("Yasal Uyarı")
                            .foregroundStyle(Color.textTertiary)
                    }

                    // Görünüm
                    Section {
                        Picker("Tema", selection: $colorScheme) {
                            Text("Sistem").tag("system")
                            Text("Karanlık").tag("dark")
                            Text("Aydınlık").tag("light")
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.surface2)
                    } header: {
                        Text("Görünüm")
                            .foregroundStyle(Color.textTertiary)
                    }

                    // AI
                    Section {
                        Toggle("AI Asistanı Etkin", isOn: $isAIEnabled)
                            .tint(Color.brandAccent)
                        if !isAIEnabled {
                            Text("AI kapalıyken asistan yalnızca kural tabanlı analizler gösterir.")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    } header: {
                        Text("Asistan")
                            .foregroundStyle(Color.textTertiary)
                    }
                    .listRowBackground(Color.surface2)

                    // Veri
                    Section {
                        HStack {
                            Text("Fiyat Yenileme Sıklığı")
                            Spacer()
                            Text("\(Int(quoteTTL)) sn")
                                .foregroundStyle(Color.textTertiary)
                        }
                        Slider(value: $quoteTTL, in: 30...300, step: 30)
                            .tint(Color.brandAccent)

                        Button {
                            Task { await refreshUniverse() }
                        } label: {
                            HStack {
                                if isRefreshingUniverse {
                                    ProgressView().scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                Text("BIST Evrenini Güncelle")
                            }
                            .foregroundStyle(Color.brandAccent)
                        }
                        .disabled(isRefreshingUniverse)

                        Button(role: .destructive) {
                            showClearCacheAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Önbelleği Temizle")
                            }
                            .foregroundStyle(Color.negative)
                        }
                    } header: {
                        Text("Veri")
                            .foregroundStyle(Color.textTertiary)
                    }
                    .listRowBackground(Color.surface2)

                    // Haberler
                    Section {
                        Toggle("Canlı Haber Kaynağı", isOn: $liveNewsEnabled)
                            .tint(Color.brandAccent)
                            .onChange(of: liveNewsEnabled) { _, _ in
                                appContainer.newsRepository.invalidate()
                            }

                        if liveNewsEnabled {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Aktif RSS Kaynakları:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.textSecondary)

                                ForEach(NewsFeed.allCases, id: \.rawValue) { feed in
                                    HStack(spacing: 8) {
                                        Image(systemName: feed.icon)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Color.brandAccent)
                                            .frame(width: 18)
                                        Text(feed.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(Color.textPrimary)
                                    }
                                }

                                Text("İnternet bağlantısı gerektirir. Haberler gerçek zamanlı olarak güncellenir.")
                                    .font(.caption2)
                                    .foregroundStyle(Color.textTertiary)
                                    .padding(.top, 2)
                            }
                            .padding(.vertical, 4)
                        } else {
                            Text("Kapalıyken örnek haberler gösterilir. Canlı haber için etkinleştirin.")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                    } header: {
                        Text("Haberler")
                            .foregroundStyle(Color.textTertiary)
                    }
                    .listRowBackground(Color.surface2)

                    // Hakkında
                    Section {
                        HStack {
                            Text("Sürüm")
                            Spacer()
                            Text("1.0.0")
                                .foregroundStyle(Color.textTertiary)
                        }
                        HStack {
                            Text("Veri Kaynağı")
                            Spacer()
                            Text(appContainer.provider.providerName)
                                .foregroundStyle(Color.textTertiary)
                        }
                        HStack {
                            Text("Veri Türü")
                            Spacer()
                            Text(appContainer.provider.isLive ? "Canlı" : "Demo (Mock)")
                                .foregroundStyle(appContainer.provider.isLive ? .positive : .neutral)
                        }
                        Button("Kullanım Koşullarını Göster") { showTerms = true }
                            .foregroundStyle(Color.brandAccent)
                        Button("Gizlilik Politikası") { showPrivacy = true }
                            .foregroundStyle(Color.brandAccent)
                    } header: {
                        Text("Hakkında")
                            .foregroundStyle(Color.textTertiary)
                    }
                    .listRowBackground(Color.surface2)

                    // Dev
                    Section {
                        Button(role: .destructive) {
                            showResetOnboarding = true
                        } label: {
                            Text("Karşılama Ekranını Sıfırla")
                                .foregroundStyle(Color.negative)
                        }
                    } header: {
                        Text("Geliştirici")
                            .foregroundStyle(Color.textTertiary)
                    }
                    .listRowBackground(Color.surface2)

                    // İmza
                    Section {
                        VStack(spacing: 6) {
                            Text("BIST Radar AI")
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Color.brandAccent)
                            Text("Developed by Utku Çetin")
                                .font(.caption)
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Color.surface1, for: .navigationBar)
            .sheet(isPresented: $showFullDisclaimer) {
                FullDisclaimerSheet()
            }
            .sheet(isPresented: $showTerms) {
                LegalTextSheet(title: "Kullanım Koşulları", content: LegalText.terms)
            }
            .sheet(isPresented: $showPrivacy) {
                LegalTextSheet(title: "Gizlilik Politikası", content: LegalText.privacy)
            }
            .alert("Önbellek Temizlensin mi?", isPresented: $showClearCacheAlert) {
                Button("Temizle", role: .destructive) {
                    Task { await DiskCache.shared.clearAll() }
                    AppCaches.quotes.removeAll()
                    AppCaches.candles.removeAll()
                    AppCaches.fundas.removeAll()
                }
                Button("İptal", role: .cancel) {}
            } message: {
                Text("Önbellek temizlendikten sonra veriler yeniden indirilecektir.")
            }
            .alert("Karşılama Ekranı", isPresented: $showResetOnboarding) {
                Button("Sıfırla", role: .destructive) { hasSeenOnboarding = false }
                Button("İptal", role: .cancel) {}
            }
        }
    }

    private func refreshUniverse() async {
        isRefreshingUniverse = true
        await appContainer.universeRepository.forceRefresh(modelContext: modelContext)
        isRefreshingUniverse = false
    }
}

// MARK: - Full Disclaimer Sheet
struct FullDisclaimerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface1.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Image(systemName: "shield.checkered")
                            .font(.system(size: 50, weight: .thin))
                            .foregroundStyle(Color.negative)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 20)

                        Text(DisclaimerText.full)
                            .font(.body)
                            .foregroundStyle(Color.textSecondary)

                        Spacer()
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Yasal Uyarı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(Color.brandAccent)
                }
            }
        }
    }
}

// MARK: - Reusable Legal Text Sheet
struct LegalTextSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let content: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface1.ignoresSafeArea()
                ScrollView {
                    Text(content)
                        .font(.callout)
                        .foregroundStyle(Color.textSecondary)
                        .padding(24)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surface1, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat") { dismiss() }
                        .foregroundStyle(Color.brandAccent)
                }
            }
        }
    }
}

// MARK: - Legal content
enum LegalText {
    static let terms = """
    BIST Radar AI — Kullanım Koşulları
    Son Güncelleme: Mart 2026

    1. GENEL
    Bu uygulama ("BIST Radar AI"), yalnızca eğitim ve bilgilendirme amacıyla geliştirilmiştir. Uygulama, Türkiye Sermaye Piyasası Kurulu (SPK) tarafından lisanslı bir yatırım danışmanlığı hizmeti değildir.

    2. YASAL UYARI
    Uygulama içinde yer alan hiçbir içerik, analiz, grafik veya yapay zeka çıktısı, yatırım tavsiyesi, alım-satım sinyali veya finansal öneri niteliği taşımaz. Kullanıcı, tüm yatırım kararlarını kendi sorumluluğu altında ve gerekirse lisanslı bir yatırım danışmanına danışarak verir.

    3. VERİ DOĞRULUĞU
    Sunulan piyasa verileri gecikmeli veya yaklaşık olabilir. Gerçek zamanlı işlemler için yetkili bir aracı kurum platformu kullanmanız zorunludur. Geliştirici, veri hataları nedeniyle doğacak zararlardan sorumlu tutulamaz.

    4. KULLANICI SORUMLULUĞU
    Kullanıcı, uygulamayı yalnızca yasal amaçlarla kullanmayı kabul eder. Uygulama verilerinin ticari amaçlarla yeniden dağıtılması yasaktır.

    5. FİKRİ MÜLKİYET
    Uygulama arayüzü, tasarımı ve kaynak kodu geliştiriciye aittir. İzinsiz kopyalanamaz veya dağıtılamaz.

    6. DEĞİŞİKLİK HAKKI
    Geliştirici, bu koşulları önceden bildirmeksizin değiştirme hakkını saklı tutar.
    """

    static let privacy = """
    BIST Radar AI — Gizlilik Politikası
    Son Güncelleme: Mart 2026

    1. TOPLANAN VERİLER
    BIST Radar AI, kullanıcı kimliğini tanımlayan herhangi bir kişisel veri toplamamaktadır. Uygulama yalnızca cihaz üzerinde çalışır ve harici bir sunucuya kişisel veri göndermez.

    2. CİHAZ İÇİ DEPOLAMA
    Uygulama, performans için fiyat verileri ve teknik göstergeleri yalnızca cihazın yerel depolama alanında (SwiftData / disk önbelleği) saklar. Bu veriler kullanıcı tarafından Ayarlar > Önbelleği Temizle ile silinebilir.

    3. ÜÇÜNCÜ TARAF HİZMETLER
    Uygulama, piyasa verileri için harici kaynaklara bağlanabilir. Bu kaynakların gizlilik politikaları kendi belgeleri kapsamındadır.

    4. ANALİTİK
    Uygulama, kullanım analizi veya crash reporting amacıyla hiçbir üçüncü taraf analitik SDK kullanmamaktadır.

    5. ÇOCUKLARIN GİZLİLİĞİ
    Bu uygulama 18 yaş altı kullanıcılara yönelik değildir ve onlardan bilinçli olarak veri toplamaz.

    6. İLETİŞİM
    Gizlilik ile ilgili sorularınız için uygulama içi destek kanalını kullanabilirsiniz.
    """
}
