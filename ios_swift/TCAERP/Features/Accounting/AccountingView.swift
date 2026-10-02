import SwiftUI

/// Accounting for Tunisia / Libya (src/features/accounting/AccountingPage.jsx):
/// invoices, treasury, banking and stats.
struct AccountingView: View {
    enum Section: String, CaseIterable, Identifiable {
        case invoices, treasury, banking, stats
        var id: String { rawValue }
        var label: String { tr("accounting.\(rawValue)") }
        var icon: String {
            switch self {
            case .invoices: return "doc.text"
            case .treasury: return "banknote"
            case .banking: return "building.columns"
            case .stats: return "chart.bar"
            }
        }
    }

    @EnvironmentObject private var router: Router
    @State private var section: Section = .invoices
    @State private var summary = (invoices: 0, monthSpending: 0.0, bankTotal: 0.0)
    @State private var refreshToken = UUID()

    private var country: Country { router.accountingCountry }

    var body: some View {
        List {
            SwiftUI.Section {
                VStack(spacing: 12) {
                    Picker(tr("common.country"), selection: $router.accountingCountry) {
                        ForEach(Country.allCases) { c in
                            Text("\(c.flag) \(c.label)").tag(c)
                        }
                    }
                    .pickerStyle(.segmented)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            StatTile(label: tr("accounting.invoicesReceipts"), value: "\(summary.invoices)", accent: .accentPurple)
                                .frame(width: 160)
                            StatTile(label: tr("accounting.monthlyOutflow"), value: Fmt.money(summary.monthSpending, country.currency), accent: .accentOrange)
                                .frame(width: 190)
                            StatTile(label: "\(tr("accounting.bankReserves")) (\(country.currency))", value: Fmt.money(summary.bankTotal, country.currency), accent: .accentGreen)
                                .frame(width: 190)
                        }
                        .padding(.vertical, 2)
                    }

                    IconTabPicker(items: Section.allCases.map { .init(value: $0, label: $0.label, systemImage: $0.icon) },
                                  selection: $section)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                .listRowBackground(Color.clear)
            }

            switch section {
            case .invoices: InvoicesSection(country: country, onChange: reload)
            case .treasury: TreasurySection(country: country, onChange: reload)
            case .banking: BankingSection(country: country, onChange: reload)
            case .stats: TreasuryStatsSection(country: country)
            }
        }
        .id(country) // fresh section state when switching country
        .navigationTitle("\(tr("accounting.accountingTitle")) \(country.flag)")
        .navigationBarTitleDisplayMode(.inline)
        .rootToolbar()
        .task(id: "\(country.rawValue)-\(refreshToken)") { await loadSummary() }
    }

    private func reload() { refreshToken = UUID() }

    private func loadSummary() async {
        let query = ["country": country.rawValue]
        let invoices: (items: [Invoice], total: Int)? = try? await API.shared.getPage("/invoices", query: query, limit: 1, offset: 0)
        let treasury: TreasuryResponse? = try? await API.shared.get("/treasury", query: query)
        let accounts: [BankAccount] = (try? await API.shared.get("/banking/accounts", query: query)) ?? []
        summary = (invoices?.total ?? 0, treasury?.currentMonth.spending ?? 0, accounts.reduce(0) { $0 + $1.balance })
    }
}

// MARK: Invoices

struct InvoicesSection: View {
    let country: Country
    var onChange: () -> Void

    private let pageSize = 25
    @StateObject private var previewer = FilePreviewer()
    @State private var invoices: [Invoice] = []
    @State private var total = 0
    @State private var query = ""
    @State private var loadedQuery = ""
    @State private var loadingMore = false
    @State private var showNew = false
    @State private var editing: Invoice?
    @State private var toRemove: Invoice?

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    private var params: [String: String] {
        var p = ["country": country.rawValue]
        if !trimmedQuery.isEmpty { p["q"] = trimmedQuery }
        return p
    }

    var body: some View {
        Section {
            Button { showNew = true } label: {
                Label(tr("invoicesTab.newDocument"), systemImage: "plus.circle.fill")
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Color.muted)
                TextField(tr("invoicesTab.searchPlaceholder"), text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if invoices.isEmpty {
                EmptyRow(text: tr("invoicesTab.noDocuments"), systemImage: "doc.text")
            }
            ForEach(invoices) { invoice in
                Button {
                    Task { await previewer.open(invoice.pdfUrl, filename: "\(invoice.number).pdf", failure: tr("invoicesTab.downloadFailed")) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: invoice.docType == "facture" ? "doc.text.fill" : "receipt")
                            .foregroundStyle(invoice.docType == "facture" ? Color.accentPurple : Color.accentOrange)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invoice.number).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                            Text("\(invoice.clientName) · \(invoice.issueDate)").font(.caption).foregroundStyle(Color.muted)
                        }
                        Spacer()
                        if previewer.loadingPath == invoice.pdfUrl {
                            ProgressView()
                        } else {
                            Text(invoice.docType == "facture" ? tr("invoicesTab.facture") : tr("invoicesTab.recu"))
                                .font(.caption).foregroundStyle(Color.muted)
                            Image(systemName: "arrow.down.doc").foregroundStyle(Color.brand)
                        }
                    }
                }
                .onAppear {
                    if invoice.id == invoices.last?.id { Task { await loadMore() } }
                }
                .swipeActions(edge: .leading) {
                    Button { editing = invoice } label: {
                        Label(tr("invoicesTab.edit"), systemImage: "pencil")
                    }
                    .tint(.blue)
                }
                .swipeActions {
                    Button { toRemove = invoice } label: {
                        Label(tr("invoicesTab.remove"), systemImage: "trash")
                    }
                    .tint(.red)
                }
                .contextMenu {
                    Button { editing = invoice } label: { Label(tr("invoicesTab.edit"), systemImage: "pencil") }
                }
            }
            if invoices.count < total {
                if loadingMore {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else {
                    Button(tr("clients.loadMore")) { Task { await loadMore() } }
                }
            }
        } header: {
            Text("\(tr("invoicesTab.documentsFor")) — \(country.label)")
        }
        .task(id: trimmedQuery) {
            if trimmedQuery != loadedQuery { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            loadedQuery = trimmedQuery
            await load()
        }
        .filePreview(previewer)
        .sheet(isPresented: $showNew) {
            NavigationStack {
                InvoiceFormView(country: country) {
                    Task { await load() }
                    onChange()
                }
            }
        }
        .sheet(item: $editing) { invoice in
            NavigationStack {
                InvoiceFormView(country: country, editing: invoice) {
                    Task { await load() }
                    onChange()
                }
            }
        }
        .confirmationDialog(tr("invoicesTab.removeConfirm"), isPresented: Binding(
            get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }
        ), titleVisibility: .visible) {
            Button(tr("invoicesTab.remove"), role: .destructive) {
                if let invoice = toRemove {
                    Task {
                        try? await API.shared.delete("/invoices/\(invoice.id)")
                        await load()
                        onChange()
                    }
                }
            }
        }
    }

    private func load() async {
        guard let page: (items: [Invoice], total: Int) = try? await API.shared.getPage("/invoices", query: params, limit: pageSize, offset: 0),
              !Task.isCancelled else { return }
        invoices = page.items
        total = page.total
    }

    private func loadMore() async {
        guard invoices.count < total, !loadingMore else { return }
        loadingMore = true
        defer { loadingMore = false }
        let key = trimmedQuery
        if let page: (items: [Invoice], total: Int) = try? await API.shared.getPage("/invoices", query: params, limit: pageSize, offset: invoices.count),
           key == trimmedQuery {
            invoices += page.items
            total = page.total
        }
    }
}

struct InvoiceFormView: View {
    let country: Country
    var editing: Invoice?
    var onCreated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var docType = "facture"
    @State private var clientName = ""
    @State private var clientPassport = ""
    @State private var clientMf = ""
    @State private var companyName = ""
    @State private var serviceType = ""
    @State private var issueDate = Fmt.today()
    @State private var tvaRate = "0.19"
    @State private var timbre = "1"
    @State private var amountPaid = ""
    @State private var items: [ItemDraft] = [ItemDraft()]
    @State private var clientID: Int?
    @State private var pickerQuery = ""
    @State private var matches: [Client] = []
    @State private var busy = false

    struct ItemDraft: Identifiable {
        let id = UUID()
        var designation = ""
        var quantity = "1"
        var unitPrice = ""
    }

    private var isFacture: Bool { docType == "facture" }

    init(country: Country, editing: Invoice? = nil, onCreated: @escaping () -> Void) {
        self.country = country
        self.editing = editing
        self.onCreated = onCreated
        guard let inv = editing else { return }
        func text(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(v) }
        _docType = State(initialValue: inv.docType)
        _clientName = State(initialValue: inv.clientName)
        _clientPassport = State(initialValue: inv.clientPassport ?? "")
        _clientMf = State(initialValue: inv.clientMf ?? "")
        _companyName = State(initialValue: inv.companyName ?? "")
        _serviceType = State(initialValue: inv.serviceType ?? "")
        _issueDate = State(initialValue: inv.issueDate)
        _tvaRate = State(initialValue: text(inv.tvaRate))
        _timbre = State(initialValue: text(inv.timbre))
        _amountPaid = State(initialValue: text(inv.amountPaid))
        _clientID = State(initialValue: inv.clientId)
        if !inv.items.isEmpty {
            _items = State(initialValue: inv.items.map {
                ItemDraft(designation: $0.designation, quantity: text($0.quantity), unitPrice: text($0.unitPrice))
            })
        }
    }

    var body: some View {
        Form {
            Section {
                Picker(tr("invoicesTab.docType").capitalizedFirst, selection: $docType) {
                    Text(tr("invoicesTab.facture")).tag("facture")
                    Text(tr("invoicesTab.recu")).tag("recu")
                }
                .pickerStyle(.segmented)
                .disabled(editing != nil)
                if editing != nil {
                    Text(tr("invoicesTab.lockedHint")).font(.caption).foregroundStyle(Color.muted)
                }
            }

            Section(tr("invoicesTab.client")) {
                LabeledField(label: tr("invoicesTab.clientName"), text: $clientName, autocapitalize: .words)
                HStack {
                    Image(systemName: "person.crop.circle.badge.plus").foregroundStyle(Color.muted)
                    TextField(tr("clients.title"), text: $pickerQuery)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                ForEach(matches) { client in
                    Button("\(client.fullName) · \(client.passportNumber)") {
                        fill(from: client)
                        pickerQuery = ""
                    }
                }
                LabeledField(label: tr("invoicesTab.clientPassport"), text: $clientPassport, autocapitalize: .characters)
                LabeledField(label: tr("invoicesTab.matriculeFiscal"), text: $clientMf, autocapitalize: .characters)
                LabeledField(label: tr("invoicesTab.companyName"), text: $companyName, autocapitalize: .words)
                if !isFacture {
                    LabeledField(label: tr("invoicesTab.serviceType"), text: $serviceType)
                }
            }

            Section {
                DateField(label: tr("invoicesTab.issueDate"), text: $issueDate)
                if isFacture {
                    LabeledField(label: tr("invoicesTab.tvaRate"), text: $tvaRate, keyboard: .decimalPad)
                    LabeledField(label: tr("invoicesTab.timbre"), text: $timbre, keyboard: .decimalPad)
                }
                LabeledField(label: tr("invoicesTab.amountPaid"), text: $amountPaid, keyboard: .decimalPad)
            }

            if isFacture {
                Section(tr("invoicesTab.lineItems")) {
                    ForEach($items) { $item in
                        VStack(spacing: 8) {
                            TextField(tr("invoicesTab.designation"), text: $item.designation)
                            HStack {
                                TextField(tr("invoicesTab.qty"), text: $item.quantity)
                                    .keyboardType(.decimalPad)
                                    .frame(maxWidth: 80)
                                Divider()
                                TextField(tr("invoicesTab.unitPrice"), text: $item.unitPrice)
                                    .keyboardType(.decimalPad)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button(tr("invoicesTab.addLineItem")) { items.append(ItemDraft()) }
                }
            }

            Section {
                PrimaryButton(title: editing != nil ? tr("invoicesTab.saveChanges") : (isFacture ? tr("invoicesTab.createFacture") : tr("invoicesTab.createRecu")), loading: busy) {
                    Task { await submit() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(editing == nil ? tr("invoicesTab.newDocument") : tr("invoicesTab.editingInvoice"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(tr("common.cancel")) { dismiss() }
            }
        }
        .task(id: pickerQuery) {
            // Client picker: the server searches, nothing is preloaded.
            let q = pickerQuery.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { matches = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let page: (items: [Client], total: Int)? = try? await API.shared.getPage("/clients", query: ["q": q], limit: 6, offset: 0)
            if !Task.isCancelled { matches = page?.items ?? [] }
        }
    }

    private func fill(from client: Client) {
        clientID = client.id
        clientName = client.fullName
        clientPassport = client.passportNumber
        if let mf = client.codeFiscal { clientMf = mf }
        if let company = client.entrepriseName { companyName = company }
    }

    private func submit() async {
        guard let name = clientName.nilIfBlank else {
            toast(tr("invoicesTab.nameRequired"), error: true)
            return
        }
        busy = true
        defer { busy = false }
        let lineItems: [InvoiceItem] = isFacture
            ? items.compactMap { item in
                guard let designation = item.designation.nilIfBlank, let price = Fmt.parse(item.unitPrice) else { return nil }
                return InvoiceItem(designation: designation, quantity: Fmt.parse(item.quantity) ?? 1, unitPrice: price)
            }
            : []
        if let editing {
            let update = InvoiceUpdate(
                clientId: clientID, clientName: name, clientPassport: clientPassport.nilIfBlank,
                clientMf: clientMf.nilIfBlank, companyName: companyName.nilIfBlank,
                serviceType: serviceType.nilIfBlank, issueDate: issueDate,
                tvaRate: Fmt.parse(tvaRate) ?? 0.19, timbre: Fmt.parse(timbre) ?? 1,
                amountPaid: Fmt.parse(amountPaid) ?? 0, items: lineItems)
            do {
                let _: Invoice = try await API.shared.put("/invoices/\(editing.id)", body: update)
                toast(tr("invoicesTab.updated"))
                onCreated()
                dismiss()
            } catch {
                toast("\(tr("invoicesTab.updateFailed")) — \(error.localizedDescription)", error: true)
            }
            return
        }
        let payload = NewInvoice(
            country: country.rawValue,
            docType: docType,
            clientName: name,
            clientPassport: clientPassport.nilIfBlank,
            clientMf: clientMf.nilIfBlank,
            companyName: companyName.nilIfBlank,
            serviceType: serviceType.nilIfBlank,
            issueDate: issueDate,
            tvaRate: Fmt.parse(tvaRate) ?? 0.19,
            timbre: Fmt.parse(timbre) ?? 1,
            amountPaid: Fmt.parse(amountPaid) ?? 0,
            items: lineItems
        )
        do {
            let _: Invoice = try await API.shared.post("/invoices", body: payload)
            toast(tr("invoicesTab.created"))
            onCreated()
            dismiss()
        } catch {
            toast("\(tr("invoicesTab.createFailed")) — \(error.localizedDescription)", error: true)
        }
    }
}

// MARK: Treasury

struct TreasurySection: View {
    let country: Country
    var onChange: () -> Void

    @EnvironmentObject private var auth: AuthStore
    @State private var data: TreasuryResponse?
    @State private var showNew = false

    var body: some View {
        if let month = data?.currentMonth {
            Section {
                HStack(spacing: 10) {
                    StatTile(label: tr("treasuryTab.gatheringThisMonth"), value: Fmt.num(month.gathering), note: country.currency, accent: .success)
                    StatTile(label: tr("treasuryTab.spendingThisMonth"), value: Fmt.num(month.spending), note: country.currency, accent: .danger)
                }
                StatTile(label: tr("treasuryTab.netResets"), value: Fmt.money(month.net, country.currency), accent: .brand)
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }

        Section {
            Button { showNew = true } label: {
                Label(tr("treasuryTab.newEntry"), systemImage: "plus.circle.fill")
            }
            let entries = data?.currentMonth.entries ?? []
            if entries.isEmpty {
                EmptyRow(text: tr("treasuryTab.noEntries"), systemImage: "banknote")
            }
            ForEach(entries) { entry in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: entry.kind == "gathering" ? "arrow.down.circle.fill" : "arrow.up.circle.fill")
                        .foregroundStyle(entry.kind == "gathering" ? Color.success : Color.danger)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.productName).font(.subheadline.weight(.semibold))
                        Text(entry.entryDate).font(.caption).foregroundStyle(Color.muted)
                        let people = [entry.recordedBy, entry.counterparty].compactMap { $0?.nilIfBlank }
                        if !people.isEmpty {
                            Text(people.joined(separator: " → ")).font(.caption).foregroundStyle(Color.muted)
                        }
                    }
                    Spacer()
                    Text(Fmt.money(entry.price, country.currency))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(entry.kind == "gathering" ? Color.success : Color.danger)
                }
                .swipeActions {
                    Button(tr("treasuryTab.remove"), role: .destructive) {
                        Task {
                            try? await API.shared.delete("/treasury/\(entry.id)")
                            await load()
                            onChange()
                        }
                    }
                }
            }
        } header: {
            Text(tr("treasuryTab.thisMonthTx"))
        }
        .task { await load() }
        .sheet(isPresented: $showNew) {
            NavigationStack {
                TreasuryEntryForm(country: country, defaultRecorder: auth.user?.name ?? "") {
                    Task { await load() }
                    onChange()
                }
            }
        }
    }

    private func load() async {
        data = try? await API.shared.get("/treasury", query: ["country": country.rawValue])
    }
}

struct TreasuryEntryForm: View {
    let country: Country
    let defaultRecorder: String
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var kind = "spending"
    @State private var product = ""
    @State private var price = ""
    @State private var date = Fmt.today()
    @State private var recordedBy = ""
    @State private var counterparty = ""
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                Picker(tr("treasuryTab.kind").capitalizedFirst, selection: $kind) {
                    Text(tr("treasuryTab.spending")).tag("spending")
                    Text(tr("treasuryTab.gathering")).tag("gathering")
                }
                .pickerStyle(.segmented)
                LabeledField(label: tr("treasuryTab.productService"), text: $product)
                LabeledField(label: "\(tr("treasuryTab.price")) (\(country.currency))", text: $price, keyboard: .decimalPad)
                DateField(label: tr("treasuryTab.date"), text: $date)
            }
            Section {
                LabeledField(label: tr("treasuryTab.recordedBy"), text: $recordedBy, placeholder: tr("treasuryTab.recordedByPlaceholder"), autocapitalize: .words)
                LabeledField(label: tr("treasuryTab.counterparty"), text: $counterparty, placeholder: tr("treasuryTab.counterpartyPlaceholder"), autocapitalize: .words)
            }
            Section {
                PrimaryButton(title: tr("treasuryTab.addEntry"), loading: busy) { Task { await submit() } }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(tr("treasuryTab.newEntry"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("common.cancel")) { dismiss() } }
        }
        .onAppear { if recordedBy.isEmpty { recordedBy = defaultRecorder } }
    }

    private func submit() async {
        guard let name = product.nilIfBlank, let amount = Fmt.parse(price) else {
            toast(tr("treasuryTab.required"), error: true)
            return
        }
        busy = true
        defer { busy = false }
        do {
            let _: TreasuryEntry = try await API.shared.post("/treasury", body: NewTreasuryEntry(
                country: country.rawValue, kind: kind, productName: name, price: amount,
                entryDate: date, recordedBy: recordedBy.nilIfBlank, counterparty: counterparty.nilIfBlank
            ))
            toast(tr("treasuryTab.recorded"))
            onSaved()
            dismiss()
        } catch {
            toast("\(tr("treasuryTab.saveFailed")) — \(error.localizedDescription)", error: true)
        }
    }
}

// MARK: Stats

struct TreasuryStatsSection: View {
    let country: Country
    @State private var history: [TreasuryMonth] = []

    var body: some View {
        Section {
            if history.isEmpty {
                EmptyRow(text: tr("statsTab.noHistory"), systemImage: "chart.bar")
            } else {
                TreasuryBarChart(data: history)
                    .frame(height: 280)
                    .padding(.vertical, 8)
            }
        } header: {
            Text("\(tr("statsTab.title")) \(country.label)")
        } footer: {
            Text("\(tr("statsTab.subtitle")) \(country.currency).")
        }
        .task {
            let data: TreasuryResponse? = try? await API.shared.get("/treasury", query: ["country": country.rawValue])
            history = data?.history ?? []
        }
    }
}
