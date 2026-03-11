# BIST Radar AI

**BIST Radar AI**, Borsa İstanbul'daki hisse senetlerini takip etmenizi, teknik analiz yapmanızı ve yapay zeka destekli yorumlar almanızı sağlayan bir iOS uygulamasıdır.

[![App Store](https://img.shields.io/badge/App%20Store'dan%20İndir-0D96F6?style=for-the-badge&logo=apple&logoColor=white)](https://apps.apple.com/tr/app/bist-radar-ai/id6760137714?l=tr)

---

## Özellikler

- **Piyasa Özeti** — BIST 100, BIST 30 ve sektör bazlı anlık takip
- **Teknik Analiz** — RSI, MACD, Bollinger Bands, EMA/SMA ve daha fazlası
- **AI Asistan** — GPT-4o destekli hisse analizi ve soru-cevap
- **Haberler** — Canlı RSS kaynakları ile piyasa haberleri
- **İzleme Listesi** — Favori hisselerinizi kaydedin
- **Fiyat Alarmları** — Belirli seviyelerde bildirim alın
- **Sektör Analizi** — Sektör bazında performans karşılaştırması
- **Karanlık / Aydınlık Tema** — Sistem temasına uyumlu

---

## Ekran Görüntüleri

> App Store'da görmek için [buraya tıklayın](https://apps.apple.com/tr/app/bist-radar-ai/id6760137714?l=tr).

---

## Kurulum (Geliştirici)

### Gereksinimler

- Xcode 15+
- iOS 17+
- OpenAI API anahtarı ([platform.openai.com/api-keys](https://platform.openai.com/api-keys))

### Adımlar

1. Repoyu klonlayın:
   ```bash
   git clone https://github.com/Cayen26/BIST-Radar.git
   cd BIST-Radar
   ```

2. `BIST Radar/Assistant/LLMService.swift` dosyasını açın ve `YOUR_OPENAI_API_KEY_HERE` kısmını kendi API anahtarınızla değiştirin:
   ```swift
   apiKey: "sk-...",  // Buraya kendi anahtarınızı yazın
   ```

3. `BIST Radar.xcodeproj` dosyasını Xcode ile açın.

4. Hedef cihazı seçip **Run** yapın (`Cmd + R`).

---

## Teknolojiler

| Katman | Teknoloji |
|---|---|
| UI | SwiftUI |
| Veri Kalıcılığı | SwiftData |
| Ağ | URLSession + async/await |
| AI | OpenAI GPT-4o (direct API) |
| Teknik Göstergeler | Native Swift (RSI, MACD, BB, EMA...) |
| Haberler | RSS / XML parsing |

---

## Proje Yapısı

```
BIST Radar/
├── Analytics/          # Teknik göstergeler, kural motoru
├── Assistant/          # AI asistan servisi
├── Data/
│   ├── Cache/          # Disk ve bellek önbelleği
│   ├── Network/        # HTTP istemcisi, RSS çekici
│   ├── Providers/      # Canlı / Mock veri sağlayıcıları
│   └── Repositories/   # Hisse, haberler, izleme listesi
├── Domain/
│   └── Models/         # Veri modelleri
├── Presentation/       # SwiftUI ekranları ve view model'lar
└── Extensions/         # Renk teması, String yardımcıları
```

---

## Yasal Uyarı

Bu uygulama yalnızca **eğitim ve bilgilendirme** amaçlıdır. İçindeki hiçbir analiz veya yapay zeka çıktısı yatırım tavsiyesi niteliği taşımaz. Tüm yatırım kararları kullanıcının kendi sorumluluğundadır.

---

## Geliştirici

**Utku Çetin**

[![App Store](https://img.shields.io/badge/App%20Store-BIST%20Radar%20AI-0D96F6?style=flat&logo=apple)](https://apps.apple.com/tr/app/bist-radar-ai/id6760137714?l=tr)
