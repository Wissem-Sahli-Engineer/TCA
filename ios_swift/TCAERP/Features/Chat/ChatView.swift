import SwiftUI

/// Local LLM assistant (ChatbotPage.jsx / ChatbotPanel.jsx). When opened
/// from the toolbar it carries a snapshot of the screen underneath, which
/// can be attached to the next message — the web's "Live helper".
struct ChatView: View {
    let snapshot: UIImage?
    let showsClose: Bool

    @EnvironmentObject private var chat: ChatStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var attachScreen = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        Text(tr("chatbot.kicker").uppercased())
                            .font(.caption2.weight(.semibold))
                            .tracking(1.2)
                            .foregroundStyle(Color.muted)
                            .padding(.top, 8)
                        ForEach(chat.messages) { message in
                            Bubble(message: message).id(message.id)
                        }
                        if chat.loading {
                            HStack {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text(tr("chatbot.thinking")).foregroundStyle(Color.muted)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .background(Color.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                Spacer()
                            }
                            .id("loading")
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: chat.messages.count) { _, _ in scrollToEnd(proxy) }
                .onChange(of: chat.loading) { _, _ in scrollToEnd(proxy) }
                .onAppear { scrollToEnd(proxy, animated: false) }
            }

            VStack(spacing: 8) {
                if let snapshot {
                    Toggle(isOn: $attachScreen) {
                        HStack(spacing: 8) {
                            Image(uiImage: snapshot)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 26, height: 40)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(tr("chat.attachScreen")).font(.caption)
                        }
                    }
                    .tint(.brand)
                }
                HStack(alignment: .bottom, spacing: 10) {
                    TextField(tr("chatbot.askPlaceholder"), text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($focused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Button {
                        send()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 34))
                    }
                    .disabled(chat.loading || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel(tr("chatbot.send"))
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .navigationTitle(tr("chatbot.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("common.close")) { dismiss() }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button(tr("chat.clear"), systemImage: "trash", role: .destructive) { chat.reset() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear { chat.ensureStarter() }
    }

    private func send() {
        let text = draft
        draft = ""
        let image = attachScreen ? snapshot : nil
        attachScreen = false
        Task { await chat.send(text, image: image) }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let target: AnyHashable? = chat.loading ? AnyHashable("loading") : chat.messages.last.map { AnyHashable($0.id) }
        guard let target else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .bottom) }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }
}

private struct Bubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 48) }
            Text(message.content)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .foregroundStyle(isUser ? Color.white : Color.ink)
                .background(isUser ? Color.brand : Color.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            if !isUser { Spacer(minLength: 48) }
        }
    }
}
