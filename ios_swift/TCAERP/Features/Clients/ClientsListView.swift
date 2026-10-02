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
        func matches(_ client: Client) -> Bool {
            switch self {
            case .all: return true
            case .fair: return client.clientCategory == .fair
            case .reservation: return client.clientCategory == .reservation
            case .alert: return client.isAlert
            }
        }
    }

    @State private var clients: [Client] = []
    @State private var tab: Tab = .all
    @State private var query = ""
    @State private var statusFilter: VisaStatus?
    @State private var error: String?
    @State private var loaded = false
    @State private var path: [Int] = []
    @State private var showAdd = false

    private var filtered: [Client] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        return clients.filter { client in
            let matchesQuery = q.isEmpty
                || client.fullName.lowercased().contains(q)
                || client.passportNumber.lowercased().contains(q)
                || (client.phone ?? "").contains(q)
            let matchesStatus = statusFilter == nil || client.visa == statusFilter
            return tab.matches(client) && matchesQuery && matchesStatus
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    IconTabPicker(items: Tab.allCases.map { tab in
                        .init(value: tab, label: tab.label, systemImage: tab.icon,
                              badge: tab == .alert ? clients.filter(\.isAlert).count : nil)
                    }, selection: $tab)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                    .listRowBackground(Color.clear)
                }
                if !loaded {
                    HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
                } else if filtered.isEmpty {
                    EmptyRow(text: error ?? tr("clients.noMatches"), systemImage: error == nil ? "person.crop.circle.badge.questionmark" : "wifi.exclamationmark")
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filtered) { client in
                        NavigationLink(value: client.id) { ClientRow(client: client) }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: tr("clients.filterPlaceholder"))
            .navigationTitle(tr("clients.title"))
            .navigationDestination(for: Int.self) { id in
                ClientDetailView(clientID: id, onChange: { Task { await load() } })
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
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    ClientFormView(mode: .add) { saved in
                        Task {
                            await load()
                            path = [saved.id]
                        }
                    }
                }
            }
        }
    }

    private func load() async {
        do {
            clients = try await API.shared.get("/clients")
            error = nil
        } catch {
            self.error = tr("clients.serverError")
        }
        loaded = true
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
        }
        .padding(.vertical, 4)
    }
}
