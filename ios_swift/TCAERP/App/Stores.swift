import SwiftUI

/// Header bell data (src/components/NotificationBell.jsx): clients whose visa
/// was rejected, plus this month's treasury net per country (admins only —
/// agents get 403 from /treasury). Refreshed every minute.
@MainActor
final class AlertsStore: ObservableObject {
    struct TreasuryNet: Identifiable {
        let country: Country
        let net: Double
        var id: String { country.rawValue }
    }

    @Published var alertClients: [Client] = []
    @Published var treasury: [TreasuryNet] = []

    var hasNegative: Bool { treasury.contains { $0.net < 0 } }
    var count: Int { alertClients.count + treasury.filter { $0.net < 0 }.count }

    func poll(isAdmin: Bool) async {
        while !Task.isCancelled {
            await load(isAdmin: isAdmin)
            try? await Task.sleep(for: .seconds(60))
        }
    }

    func load(isAdmin: Bool) async {
        if let page: (items: [Client], total: Int) = try? await API.shared.getPage("/clients", query: ["tab": "alert"], limit: 50, offset: 0) {
            alertClients = page.items
        }
        guard isAdmin else { treasury = []; return }
        var nets: [TreasuryNet] = []
        for country in Country.allCases {
            let data: TreasuryResponse? = try? await API.shared.get("/treasury", query: ["country": country.rawValue])
            nets.append(TreasuryNet(country: country, net: data?.currentMonth.net ?? 0))
        }
        treasury = nets
    }
}

/// Conversation with the local assistant, kept while the app runs so the
/// sheet and the full-screen chat share history.
@MainActor
final class ChatStore: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var loading = false

    static let modelLabel = "Qwen2.5-VL 3B"

    func ensureStarter() {
        if messages.isEmpty {
            messages = [ChatMessage(role: "assistant", content: tr("chatbot.starter").replacingOccurrences(of: "{model}", with: Self.modelLabel))]
        }
    }

    func reset() {
        messages = []
        ensureStarter()
    }

    func send(_ text: String, image: UIImage?) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !loading else { return }
        messages.append(ChatMessage(role: "user", content: text))
        loading = true
        defer { loading = false }
        do {
            let reply: ChatReply = try await API.shared.post(
                "/chat", body: ChatRequest(messages: messages, image: image?.dataURL(maxDimension: 1280))
            )
            messages.append(ChatMessage(role: "assistant", content: reply.reply ?? tr("chatbot.noResponse")))
        } catch {
            messages.append(ChatMessage(
                role: "assistant",
                content: tr("chatbot.unreachable").replacingOccurrences(of: "{error}", with: error.localizedDescription)
            ))
        }
    }
}
