// LLMService.swift – OpenAI + Anthropic direct integration + multi-turn chat
// BIST Radar AI

import Foundation

// MARK: - Provider

enum LLMProvider: String, Codable {
    case openAIDirect     // Direct OpenAI Chat Completions API
    case anthropicDirect  // Direct Anthropic Messages API
    case anthropicProxy   // Backend proxy → Anthropic (legacy)
    case openAIProxy      // Backend proxy → OpenAI (legacy)
    case disabled         // No LLM; use rule engine only
}

// MARK: - Config

struct LLMConfig {
    let provider: LLMProvider
    let apiKey: String?     // API key (direct mode)
    let proxyURL: URL?      // Backend proxy URL (proxy mode)
    let modelID: String
    let maxTokens: Int
    let timeoutSeconds: TimeInterval
}

// MARK: - Message type (role/content — compatible with both OpenAI and Anthropic)

struct AnthropicMessage: Codable, Sendable {
    let role: String   // "user" | "assistant"
    let content: String
}

// MARK: - Service

final class LLMService: Sendable {
    private let config: LLMConfig

    init(config: LLMConfig = .default) {
        self.config = config
    }

    // MARK: - Single-turn (legacy)
    func generate(prompt: String, systemPrompt: String) async throws -> String {
        let userMessage = AnthropicMessage(role: "user", content: prompt)
        return try await generate(messages: [userMessage], systemPrompt: systemPrompt)
    }

    // MARK: - Multi-turn
    func generate(messages: [AnthropicMessage], systemPrompt: String) async throws -> String {
        guard config.provider != .disabled else {
            throw LLMError.disabled
        }

        switch config.provider {
        case .openAIDirect:
            return try await callOpenAIDirect(messages: messages, systemPrompt: systemPrompt)
        case .anthropicDirect:
            return try await callAnthropicDirect(messages: messages, systemPrompt: systemPrompt)
        case .anthropicProxy, .openAIProxy:
            guard let url = config.proxyURL else { throw LLMError.disabled }
            return try await callProxy(url: url, messages: messages, systemPrompt: systemPrompt)
        case .disabled:
            throw LLMError.disabled
        }
    }

    var isEnabled: Bool {
        guard config.provider != .disabled else { return false }
        switch config.provider {
        case .openAIDirect, .anthropicDirect:
            return config.apiKey != nil && !(config.apiKey?.isEmpty ?? true)
        case .anthropicProxy, .openAIProxy:
            return config.proxyURL != nil
        case .disabled:
            return false
        }
    }

    // MARK: - Streaming (SSE)

    func generateStream(messages: [AnthropicMessage], systemPrompt: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    switch config.provider {
                    case .openAIDirect:
                        try await self.streamOpenAIDirect(messages: messages, systemPrompt: systemPrompt, continuation: continuation)
                    case .anthropicDirect:
                        try await self.streamAnthropicDirect(messages: messages, systemPrompt: systemPrompt, continuation: continuation)
                    default:
                        // Proxy / disabled — non-streaming fallback
                        let result = try await self.generate(messages: messages, systemPrompt: systemPrompt)
                        continuation.yield(result)
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func streamOpenAIDirect(
        messages: [AnthropicMessage],
        systemPrompt: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard let apiKey = config.apiKey, !apiKey.isEmpty,
              let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw LLMError.disabled
        }

        var openAIMessages: [OpenAIMessage] = [OpenAIMessage(role: "system", content: systemPrompt)]
        openAIMessages += messages.map { OpenAIMessage(role: $0.role, content: $0.content) }

        let body = OpenAIStreamRequestBody(model: config.modelID, messages: openAIMessages,
                                           max_tokens: config.maxTokens, stream: true)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BISTRadarAI/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = config.timeoutSeconds

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.requestFailed
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard json != "[DONE]" else { break }
            if let data = json.data(using: .utf8),
               let chunk = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data),
               let text = chunk.choices.first?.delta.content {
                continuation.yield(text)
            }
        }
        continuation.finish()
    }

    private func streamAnthropicDirect(
        messages: [AnthropicMessage],
        systemPrompt: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        guard let apiKey = config.apiKey, !apiKey.isEmpty,
              let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw LLMError.disabled
        }

        let body = AnthropicStreamRequestBody(model: config.modelID, max_tokens: config.maxTokens,
                                              system: systemPrompt, messages: messages, stream: true)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("BISTRadarAI/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = config.timeoutSeconds

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LLMError.requestFailed
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            if let data = json.data(using: .utf8),
               let chunk = try? JSONDecoder().decode(AnthropicStreamChunk.self, from: data),
               chunk.type == "content_block_delta" {
                continuation.yield(chunk.delta?.text ?? "")
            }
        }
        continuation.finish()
    }

    // MARK: - Direct OpenAI call

    private func callOpenAIDirect(messages: [AnthropicMessage], systemPrompt: String) async throws -> String {
        guard let apiKey = config.apiKey, !apiKey.isEmpty,
              let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            throw LLMError.disabled
        }

        // OpenAI format: system message first, then conversation history
        var openAIMessages: [OpenAIMessage] = [
            OpenAIMessage(role: "system", content: systemPrompt)
        ]
        openAIMessages += messages.map { OpenAIMessage(role: $0.role, content: $0.content) }

        let body = OpenAIRequestBody(
            model: config.modelID,
            messages: openAIMessages,
            max_tokens: config.maxTokens
        )

        let bodyData = try JSONEncoder().encode(body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BISTRadarAI/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = config.timeoutSeconds

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.requestFailed
        }
        guard httpResponse.statusCode == 200 else {
            throw LLMError.requestFailed
        }

        let decoded = try JSONDecoder().decode(OpenAIResponseBody.self, from: data)
        guard let text = decoded.choices.first?.message.content else {
            throw LLMError.requestFailed
        }
        return text
    }

    // MARK: - Direct Anthropic call

    private func callAnthropicDirect(messages: [AnthropicMessage], systemPrompt: String) async throws -> String {
        guard let apiKey = config.apiKey, !apiKey.isEmpty,
              let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw LLMError.disabled
        }

        let body = AnthropicRequestBody(
            model: config.modelID,
            max_tokens: config.maxTokens,
            system: systemPrompt,
            messages: messages
        )

        let bodyData = try JSONEncoder().encode(body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("BISTRadarAI/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = config.timeoutSeconds

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMError.requestFailed
        }

        let decoded = try JSONDecoder().decode(AnthropicResponseBody.self, from: data)
        guard let firstContent = decoded.content.first else {
            throw LLMError.requestFailed
        }
        return firstContent.text
    }

    // MARK: - Proxy call (legacy)

    private func callProxy(url: URL, messages: [AnthropicMessage], systemPrompt: String) async throws -> String {
        let lastUserMessage = messages.last(where: { $0.role == "user" })?.content ?? ""
        let payload = LLMRequestPayload(
            model: config.modelID,
            systemPrompt: systemPrompt,
            userMessage: lastUserMessage,
            maxTokens: config.maxTokens
        )
        let body = try JSONEncoder().encode(payload)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("BISTRadarAI/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = config.timeoutSeconds

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw LLMError.requestFailed
        }
        let decoded = try JSONDecoder().decode(LLMResponsePayload.self, from: data)
        return decoded.content
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case disabled
    case requestFailed
    case contentBlocked
    case overloaded

    var errorDescription: String? {
        switch self {
        case .disabled:       return "LLM devre dışı. Kural motoru kullanılıyor."
        case .requestFailed:  return "LLM isteği başarısız oldu."
        case .contentBlocked: return "İçerik güvenlik filtresi tarafından engellendi."
        case .overloaded:     return "LLM servisi şu an yoğun. Lütfen tekrar deneyin."
        }
    }
}

// MARK: - OpenAI types

private struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

private struct OpenAIRequestBody: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let max_tokens: Int
}

private struct OpenAIStreamRequestBody: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let max_tokens: Int
    let stream: Bool
}

private struct OpenAIStreamChunk: Codable {
    struct Choice: Codable {
        struct Delta: Codable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
}

private struct OpenAIResponseBody: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}

// MARK: - Anthropic types

private struct AnthropicRequestBody: Codable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [AnthropicMessage]
}

private struct AnthropicStreamRequestBody: Codable {
    let model: String
    let max_tokens: Int
    let system: String
    let messages: [AnthropicMessage]
    let stream: Bool
}

private struct AnthropicStreamChunk: Codable {
    let type: String
    struct Delta: Codable {
        let type: String?
        let text: String?
    }
    let delta: Delta?
}

private struct AnthropicResponseBody: Codable {
    struct ContentBlock: Codable {
        let type: String
        let text: String
    }
    let content: [ContentBlock]
}

// MARK: - Proxy types (legacy)

private struct LLMRequestPayload: Codable {
    let model: String
    let systemPrompt: String
    let userMessage: String
    let maxTokens: Int
}

private struct LLMResponsePayload: Codable {
    let content: String
}

// MARK: - Default config

extension LLMConfig {
    static let `default` = LLMConfig(
        provider: .openAIDirect,
        apiKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
        proxyURL: nil,
        modelID: "gpt-4o",
        maxTokens: 2048,
        timeoutSeconds: 45
    )
}

// MARK: - Prompt Templates

enum PromptTemplates {
    static let systemPrompt = """
    Sen BIST Radar AI — Türkiye borsası (BIST) konusunda uzman, samimi ve sohbet odaklı bir finans asistanısın.

    ## KİŞİLİK
    - Doğal ve akıcı konuş, robot gibi kalıp yanıtlar verme
    - Kullanıcının önceki sorularını hatırla, bağlamı koru
    - Kısa sorulara kısa, detaylı sorulara detaylı yanıt ver
    - Sohbet devam ediyorsa "Peki", "Harika soru", "Evet, buna ek olarak..." gibi geçişler kullan

    ## ZORUNLU KURALLAR
    - Tüm yanıtlar Türkçe olsun
    - "Al", "sat", "kesin kazanç" gibi yatırım tavsiyesi verme
    - Her yanıtın sonunda: ⚠️ *Bu analiz yalnızca eğitsel amaçlıdır, yatırım tavsiyesi değildir.*
    - Bağlamda gerçek fiyat verisi yoksa sayı uydurmа — yerine kavramsal açıklama yap

    ## YANIT REHBERİ

    **Kavram soruları** (RSI nedir, MACD nasıl çalışır, vb.)
    → Net, anlaşılır açıklama. Formül varsa göster. Örnek değerler ver. 100-250 kelime yeterli.

    **Hisse analizi** (bağlamda gerçek veri varsa)
    → Fiyat + trend + momentum (RSI, MACD, StochRSI) + Bollinger + destek/direnç sırasıyla analiz et.
    → Gösterge değerlerini rakamla yaz: RSI=68.4, MACD=+0.0023 gibi.

    **Genel piyasa / sohbet soruları**
    → Eğitsel ve bağlamsal yanıt ver. Kesin fiyat/yüzde uydurmа.
    → Spesifik analiz için kullanıcıyı THYAO, GARAN gibi sembol yazmaya yönlendir.

    ## GÖSTERGE REFERANSI
    RSI: <30 aşırı satım | 30-50 zayıf | 50-70 güçlü | >70 aşırı alım
    MACD: Sinyal üstünde + pozitif histogram = yükselen momentum
    Bollinger: %B>80 üst banda yakın | <20 alt banda yakın | daralma = büyük hareket öncesi
    EMA: Fiyat>EMA20>EMA50 = güçlü yükseliş trendi
    StochRSI: >80 aşırı alım | <20 aşırı satım (RSI'dan hassas)
    """

    static func userPrompt(query: String, contextData: String) -> String {
        """
        \(contextData)

        Kullanıcı: \(query)
        """
    }
}
