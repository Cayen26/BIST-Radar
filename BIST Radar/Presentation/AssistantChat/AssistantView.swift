// AssistantView.swift – BIST Asistanı chat interface
// BIST Radar AI

import SwiftUI

struct AssistantChatView: View {
    var contextSymbol: String? = nil
    @EnvironmentObject var appContainer: AppContainer
    @State private var vm: AssistantViewModel?
    @State private var showChips = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.surface1.ignoresSafeArea()

                if let vm {
                    VStack(spacing: 0) {
                        // Disclaimer banner at top
                        DisclaimerBannerView()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)

                        Divider().overlay(Color.surface3)

                        // Message list
                        ScrollViewReader { proxy in
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(vm.messages) { msg in
                                        MessageBubble(message: msg)
                                            .id(msg.id)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                            .onChange(of: vm.messages.count) { _, _ in
                                if let last = vm.messages.last {
                                    withAnimation {
                                        proxy.scrollTo(last.id, anchor: .bottom)
                                    }
                                }
                            }
                        }

                        // Quick chips panel – toggle ile açılıp kapanır
                        if showChips {
                            VStack(spacing: 0) {
                                Divider().overlay(Color.surface3)
                                ScrollView(.vertical, showsIndicators: false) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        ForEach(QuickChip.categories, id: \.self) { category in
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(category)
                                                    .font(.caption2.bold())
                                                    .foregroundStyle(Color.textSecondary)
                                                    .padding(.horizontal, 16)

                                                ScrollView(.horizontal, showsIndicators: false) {
                                                    HStack(spacing: 8) {
                                                        ForEach(QuickChip.chips(for: category)) { chip in
                                                            Button {
                                                                vm.sendChip(chip)
                                                                withAnimation(.easeInOut(duration: 0.25)) {
                                                                    showChips = false
                                                                }
                                                            } label: {
                                                                Text(chip.label)
                                                                    .font(.caption.bold())
                                                                    .foregroundStyle(Color.textPrimary)
                                                                    .padding(.horizontal, 12)
                                                                    .padding(.vertical, 8)
                                                                    .background(Color.surface3)
                                                                    .clipShape(Capsule())
                                                            }
                                                        }
                                                    }
                                                    .padding(.horizontal, 16)
                                                }
                                            }
                                        }
                                    }
                                    .padding(.vertical, 10)
                                }
                                .frame(maxHeight: 280)
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        Divider().overlay(Color.surface3)

                        // Input bar + chip toggle butonu
                        HStack(spacing: 8) {
                            // Chip toggle
                            Button {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    showChips.toggle()
                                }
                            } label: {
                                Image(systemName: showChips ? "list.bullet.circle.fill" : "list.bullet.circle")
                                    .font(.system(size: 28))
                                    .foregroundStyle(showChips ? Color.brandAccent : Color.textTertiary)
                            }

                            MessageInputBar(
                                text: Binding(
                                    get: { vm.inputText },
                                    set: { vm.inputText = $0 }
                                ),
                                isLoading: vm.isTyping,
                                onSend: { Task { await vm.send() } }
                            )
                        }
                        .padding(.leading, 12)
                        .background(Color.surface1)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("BIST Asistanı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.surface1, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        vm?.clearHistory()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .onAppear {
            if vm == nil {
                vm = AssistantViewModel(
                    assistantEngine: appContainer.assistantEngine,
                    contextSymbol: contextSymbol
                )
            }
        }
    }
}

// MARK: - Message Bubble
struct MessageBubble: View {
    let message: ChatMessage

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 50) }

            if message.isLoading {
                TypingIndicator()
                    .padding(12)
                    .background(Color.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                    Text(.init(message.content))
                        .font(.callout)
                        .foregroundStyle(Color.textPrimary)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isUser ? Color.brandAccent.opacity(0.2) : Color.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text(message.timestamp.formatted(.dateTime.hour().minute()))
                        .font(.caption2)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            if !isUser { Spacer(minLength: 50) }
        }
    }
}

// MARK: - Typing indicator (3 animated dots)
struct TypingIndicator: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.textTertiary)
                    .frame(width: 6, height: 6)
                    .scaleEffect(phase == i ? 1.3 : 0.8)
                    .animation(
                        .easeInOut(duration: 0.4)
                        .repeatForever()
                        .delay(Double(i) * 0.15),
                        value: phase
                    )
            }
        }
        .onAppear { phase = 1 }
    }
}

// MARK: - Message Input Bar
struct MessageInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            TextField("Soru sor...", text: $text, axis: .vertical)
                .font(.callout)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.surface2)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .disabled(isLoading)
                .onSubmit { if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { onSend() } }

            Button(action: onSend) {
                Image(systemName: isLoading ? "ellipsis" : "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(
                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                            ? Color.textTertiary
                            : Color.brandAccent
                    )
                    .symbolEffect(.pulse, isActive: isLoading)
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
        }
        .padding(.trailing, 16)
        .padding(.vertical, 10)
    }
}
