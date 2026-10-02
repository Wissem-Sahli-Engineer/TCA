import SwiftUI

/// Client database (src/features/clients/ClientsPage.jsx).
struct ClientsListView: View {
    /// Same tabs as the website: all, by category, and visa alerts.
    enum Tab: String, CaseIterable, Identifiable {
        case all, fair, reservation, alert
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return tr("clients.tabAll")
            case .fair: return tr("clients.tabFair")
            case .reservation: return tr("clients.tabReservation")
            case .alert: return tr("clients.tabAlert")
            }
        }
        var icon: String {
            switch self {
            case .all: return "person.2"
            case .fair: return "building.columns"
            case .reservation: return "airplane"
            case .alert: return "exclamationmark.triangle"
            }
        }
        /// The server's name for the tab (it does the filtering).
        var server: String { rawValue }
    }

    private let pageSize = 25
    @State private var clients: [Client] = []
    @State private var total = 0
    @State private var alertCount = 0
    @State private var tab: Tab = .all
    @State private var query = ""
    @State private var loadedQuery = ""
    @State private var statusFilter: VisaStatus?
    @State private var error: String?
    @State private var loaded = false
    @State private var loadingMore = false
    @State private var path: [Int] = []
    @State private var showAdd = false

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    private var filterKey: String { "\(trimmedQuery)|\(tab.rawValue)|\(statusFilter?.rawValue ?? "")" }
    private var hasMore: Bool { clients.count < total }

    /// Search, tab and status are applied by the server; only one page is downloaded at a time.
    private var params: [String: String] {
        var p = ["tab": tab.server]
        if !trimmedQuery.isEmpty { p["q"] = trimmedQuery }
        if let statusFilter { p["status"] = statusFilter.rawValue }
        return p
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    IconTabPicker(items: Tab.allCases.map { tab in
                        .init(value: tab, label: tab.label, systemImage: tab.icon,
                              badge: tab == .alert ? alertCount : nil)
                    }, selection: $tab)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                }
                if !loaded {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
                } else if clients.isEmpty {
                    EmptyRow(text: error ?? tr("clients.noMatches"), systemImage: error == nil ? "person.crop.circle.badge.questionmark" : "wifi.exclamationmark")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(clients) { client in
                        NavigationLink(value: client.id) { ClientRow(client: client) }
                            .onAppear {
                                // Reaching the last loaded row fetches the next page.
                                if client.id == clients.last?.id { Task { await loadMore() } }
                            }
                    }
                    Section {
                        if loadingMore {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else {
                            Text(tr("clients.showing")
                                .replacingOccurrences(of: "{n}", with: "\(clients.count)")
                                .replacingOccurrences(of: "{total}", with: "\(total)"))
                                .font(.footnote)
                                .foregroundStyle(Color.muted)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: tr("clients.filterPlaceholder"))
            .navigationTitle(tr("clients.title"))
            .navigationDestination(for: Int.self) { id in
                ClientDetailView(clientID: id, onChange: { Task { await loadFirstPage() } })
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker(tr("clients.visaStatus"), selection: $statusFilter) {
                            Text(tr("clients.allStatuses")).tag(VisaStatus?.none)
                            ForEach(VisaStatus.allCases) { status in
                                Text(status.label).tag(Optional(status))
                            }
                        }
                    } label: {
                        Image(systemName: statusFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel(tr("clients.addClient"))
                }
            }
            .rootToolbar()
            .refreshable { await loadFirstPage() }
            .task(id: filterKey) {
                // Typing waits for a pause; switching tab or status is instant.
                if trimmedQuery != loadedQuery { try? await Task.sleep(for: .milliseconds(300)) }
                guard !Task.isCancelled else { return }
                loadedQuery = trimmedQuery
                await loadFirstPage()
            }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    ClientFormView(mode: .add) { saved in
                        Task {
                            await loadFirstPage()
                            path = [saved.id]
                        }
                    }
                }
            }
        }
    }

    private func loadFirstPage() async {
        do {
            let page: (items: [Client], total: Int) = try await API.shared.getPage("/clients", query: params, limit: pageSize, offset: 0)
            guard !Task.isCancelled else { return }
            clients = page.items
            total = page.total
            error = nil
        } catch {
            guard !Task.isCancelled else { return }
            self.error = tr("clients.serverError")
        }
        loaded = true
        if let summary: ClientSummary = try? await API.shared.get("/clients/summary") { alertCount = summary.alerts }
    }

    private func loadMore() async {
        guard hasMore, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let key = filterKey
        if let page: (items: [Client], total: Int) = try? await API.shared.getPage("/clients", query: params, limit: pageSize, offset: clients.count),
           key == filterKey {   // ignore an answer that arrives after the filters changed
            clients += page.items
            total = page.total
        }
    }
}

struct ClientRow: View {
    let client: Client

    var body: some View {
        HStack(spacing: 12) {
            AuthImage(path: client.displayPhoto)
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(client.fullName).font(.body.weight(.semibold)).foregroundStyle(Color.ink)
                HStack(spacing: 6) {
                    Text(client.passportNumber).font(.caption.monospaced())
                    if let nationality = client.nationality, !nationality.isEmpty {
                        Text("· \(nationality)").font(.caption)
                    }
                }
                .foregroundStyle(Color.muted)
                if let phone = client.phone, !phone.isEmpty {
                    Text(phone).font(.caption).foregroundStyle(Color.muted)
                }
                ForEach(client.alertReasons, id: \.self) { reason in
                    Label(reason.text, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.danger)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(visa: client.visa)
                if let payment = client.payment {
                    StatusBadge(payment: payment)
                }
            }
            .frame(width: 112, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}
