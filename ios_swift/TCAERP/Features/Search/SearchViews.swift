import SwiftUI

/// Global search across clients and invoices (GlobalSearch.jsx).
struct SearchView: View {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var clients: [Client] = []
    @State private var invoices: [Invoice] = []
    @State private var allClients: [Client]?
    @State private var allInvoices: [Invoice]?

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }

    var body: some View {
        NavigationStack {
            List {
                if q.count < 2 {
                    EmptyRow(text: tr("search.hint"), systemImage: "magnifyingglass")
                        .listRowBackground(Color.clear)
                } else if clients.isEmpty && invoices.isEmpty {
                    EmptyRow(text: tr("search.noMatches"), systemImage: "magnifyingglass")
                        .listRowBackground(Color.clear)
                } else {
                    if !clients.isEmpty {
                        Section(tr("search.clients")) {
                            ForEach(clients) { client in
                                NavigationLink {
                                    ClientDetailView(clientID: client.id)
                                } label: {
                                    ClientRow(client: client)
                                }
                            }
                        }
                    }
                    if !invoices.isEmpty {
                        Section(tr("search.invoices")) {
                            ForEach(invoices) { invoice in
                                Button {
                                    router.accountingCountry = Country(rawValue: invoice.country) ?? .tunisia
                                    router.tab = .accounting
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(invoice.number).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                                        Text("\(invoice.clientName) · \(Country(rawValue: invoice.country)?.label ?? invoice.country)")
                                            .font(.caption).foregroundStyle(Color.muted)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: tr("header.search"))
            .navigationTitle(tr("header.search").replacingOccurrences(of: "…", with: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("common.close")) { dismiss() }
                }
            }
            .task(id: q) {
                guard q.count >= 2 else { clients = []; invoices = []; return }
                try? await Task.sleep(for: .milliseconds(250)) // debounce typing
                guard !Task.isCancelled else { return }
                await search()
            }
        }
    }

    private func search() async {
        if allClients == nil { allClients = try? await API.shared.get("/clients") }
        if allInvoices == nil {
            var list: [Invoice] = []
            if auth.isAdmin {
                for country in Country.allCases {
                    list += (try? await API.shared.get("/invoices", query: ["country": country.rawValue])) ?? []
                }
            }
            allInvoices = list
        }
        clients = Array((allClients ?? []).filter {
            $0.fullName.lowercased().contains(q) || $0.passportNumber.lowercased().contains(q)
        }.prefix(8))
        invoices = Array((allInvoices ?? []).filter {
            $0.number.lowercased().contains(q) || $0.clientName.lowercased().contains(q)
        }.prefix(8))
    }
}

/// Bell contents (NotificationBell.jsx).
struct NotificationsView: View {
    @EnvironmentObject private var alerts: AlertsStore
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if auth.isAdmin {
                    Section(tr("notifications.treasury")) {
                        ForEach(alerts.treasury) { item in
                            HStack {
                                Text("\(item.country.flag) \(item.country.label)")
                                Spacer()
                                Text(Fmt.money(item.net, item.country.currency) + (item.net < 0 ? " ⚠︎" : ""))
                                    .fontWeight(.semibold)
                                    .foregroundStyle(item.net < 0 ? Color.danger : Color.success)
                            }
                        }
                    }
                }
                Section(tr("notifications.clientsInAlert")) {
                    if alerts.alertClients.isEmpty {
                        Text(tr("notifications.noAlerts")).foregroundStyle(Color.muted)
                    }
                    ForEach(alerts.alertClients) { client in
                        NavigationLink {
                            ClientDetailView(clientID: client.id)
                        } label: {
                            HStack {
                                Text(client.fullName)
                                Spacer()
                                Text(client.alertReasons.map(\.text).joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Color.danger)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                }
            }
            .navigationTitle(tr("header.notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("common.close")) { dismiss() }
                }
            }
            .refreshable { await alerts.load(isAdmin: auth.isAdmin) }
        }
        .presentationDetents([.medium, .large])
    }
}
