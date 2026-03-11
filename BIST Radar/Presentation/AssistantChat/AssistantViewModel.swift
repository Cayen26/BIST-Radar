// AssistantViewModel.swift
// BIST Radar AI

import SwiftUI
import Observation

@Observable
final class AssistantViewModel {
    // MARK: - State
    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isTyping = false
    var contextSymbol: String?

    /// Multi-turn conversation history passed to LLM
    private(set) var conversationHistory: [AnthropicMessage] = []

    private let assistantEngine: AssistantEngine

    init(assistantEngine: AssistantEngine, contextSymbol: String? = nil) {
        self.assistantEngine = assistantEngine
        self.contextSymbol = contextSymbol
        insertWelcome()
    }

    // MARK: - Send message (streaming)
    @MainActor
    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isTyping else { return }
        inputText = ""
        isTyping = true
        defer { isTyping = false }

        messages.append(.userMessage(text, symbol: contextSymbol))

        // Boş asistan mesajı ekle — token geldikçe içi dolacak
        let streamingId = UUID()
        messages.append(ChatMessage(id: streamingId, role: .assistant,
                                    content: "", isLoading: true, relatedSymbol: contextSymbol))

        guard let idx = messages.indices.last else { return }

        do {
            var receivedAny = false
            for try await token in assistantEngine.respondStream(
                to: text,
                contextSymbol: contextSymbol,
                conversationHistory: conversationHistory
            ) {
                if !receivedAny {
                    messages[idx].isLoading = false
                    receivedAny = true
                }
                messages[idx].content += token
            }
            if !receivedAny {
                messages[idx].isLoading = false
                messages[idx].content = "Yanıt alınamadı. Lütfen tekrar deneyin."
            }
        } catch {
            messages[idx].isLoading = false
            messages[idx].content = "Bir hata oluştu: \(error.localizedDescription)"
        }

        let finalContent = messages[idx].content
        conversationHistory.append(AnthropicMessage(role: "user", content: text))
        conversationHistory.append(AnthropicMessage(role: "assistant", content: finalContent))

        if conversationHistory.count > 20 {
            conversationHistory = Array(conversationHistory.suffix(20))
        }
    }

    func sendChip(_ chip: QuickChip) {
        inputText = chip.query
        Task { await send() }
    }

    func clearHistory() {
        messages.removeAll()
        conversationHistory.removeAll()
        insertWelcome()
    }

    // MARK: - Private
    private func insertWelcome() {
        let symbolLine = contextSymbol.map { " Şu an **\($0)** hissesi bağlamındasınız." } ?? ""
        let welcome = """
        Merhaba! Ben BIST Radar AI Asistanı. 👋\(symbolLine)

        Piyasa verileri, teknik göstergeler ve finansal kavramlar hakkında Türkçe sorular sorabilirsiniz.

        Yanıtlarım yalnızca eğitsel amaçlıdır ve numerik verilere dayanır.

        **Bu bir yatırım tavsiyesi değildir.**
        """
        messages.append(.assistantMessage(welcome))
    }
}
