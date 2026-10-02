import SwiftUI

/// Bank accounts for a country (src/features/accounting/BankingTab.jsx).
struct BankingSection: View {
    let country: Country
    var onChange: () -> Void

    @State private var accounts: [BankAccount] = []
    @State private var showNew = false
    @State private var toRemove: BankAccount?

    var body: some View {
        Section {
            Button { showNew = true } label: {
                Label(tr("bankingTab.newAccount"), systemImage: "plus.circle.fill")
            }
            if accounts.isEmpty {
                EmptyRow(text: "\(tr("bankingTab.noAccounts")) \(country.label).", systemImage: "building.columns")
            }
            ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                NavigationLink {
                    BankAccountView(account: account, flag: country.flag) {
                        Task { await load() }
                        onChange()
                    }
                } label: {
                    AccountCard(account: account, flag: country.flag, highlighted: index == 0)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                .listRowBackground(index == 0 ? Color.cardInk : Color.card)
                .swipeActions {
                    Button { toRemove = account } label: {
                        Label(tr("bankingTab.remove"), systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
        } header: {
            Text(tr("bankingTab.bankAccounts"))
        }
        .task { await load() }
        .sheet(isPresented: $showNew) {
            NavigationStack {
                BankAccountForm(country: country) {
                    Task { await load() }
                    onChange()
                }
            }
        }
        .confirmationDialog(tr("bankingTab.removeAccountConfirm"), isPresented: Binding(
            get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }
        ), titleVisibility: .visible) {
            Button(tr("bankingTab.remove"), role: .destructive) {
                if let account = toRemove {
                    Task {
                        try? await API.shared.delete("/banking/accounts/\(account.id)")
                        await load()
                        onChange()
                    }
                }
            }
        }
    }

    private func load() async {
        accounts = (try? await API.shared.get("/banking/accounts", query: ["country": country.rawValue])) ?? []
    }
}

private struct AccountCard: View {
    let account: BankAccount
    let flag: String
    let highlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(account.currency) \(tr("bankingTab.accountSuffix"))".uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .opacity(0.6)
                Spacer()
                Text(flag)
            }
            Text(account.name).font(.headline)
            Text(Fmt.money(account.balance, account.currency))
                .font(.system(size: 26, weight: .heavy, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 8)
        }
        .foregroundStyle(highlighted ? Color.white : Color.ink)
        .padding(4)
    }
}

struct BankAccountForm: View {
    let country: Country
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var currency = ""
    @State private var balance = ""
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                LabeledField(label: tr("bankingTab.accountName"), text: $name, autocapitalize: .words)
                LabeledField(label: tr("bankingTab.currency"), text: $currency, placeholder: country.currency, autocapitalize: .characters)
                LabeledField(label: tr("bankingTab.openingBalance"), text: $balance, keyboard: .decimalPad)
            }
            Section {
                PrimaryButton(title: tr("bankingTab.addAccount"), loading: busy) { Task { await submit() } }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(tr("bankingTab.newAccount"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("common.cancel")) { dismiss() } }
        }
        .onAppear { if currency.isEmpty { currency = country.currency } }
    }

    private func submit() async {
        guard let accountName = name.nilIfBlank, let cur = currency.nilIfBlank else { return }
        busy = true
        defer { busy = false }
        do {
            let _: BankAccount = try await API.shared.post("/banking/accounts", body: NewBankAccount(
                country: country.rawValue, name: accountName, currency: cur.uppercased(), balance: Fmt.parse(balance) ?? 0
            ))
            toast(tr("bankingTab.accountAdded"))
            onSaved()
            dismiss()
        } catch {
            toast("\(tr("bankingTab.addAccountFailed")) — \(error.localizedDescription)", error: true)
        }
    }
}

/// Transactions for one account; deposits positive, withdrawals negative.
struct BankAccountView: View {
    let account: BankAccount
    let flag: String
    var onChange: () -> Void

    @State private var balance: Double
    @State private var transactions: [BankTransaction] = []
    @State private var showNew = false

    init(account: BankAccount, flag: String, onChange: @escaping () -> Void) {
        self.account = account
        self.flag = flag
        self.onChange = onChange
        _balance = State(initialValue: account.balance)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(account.currency) \(tr("bankingTab.accountSuffix")) \(flag)")
                        .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.6))
                    Text(Fmt.money(balance, account.currency))
                        .font(.system(size: 32, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(.vertical, 8)
                .listRowBackground(Color.cardInk)
            }

            Section {
                Button { showNew = true } label: {
                    Label(tr("bankingTab.newTransaction"), systemImage: "plus.circle.fill")
                }
                if transactions.isEmpty {
                    EmptyRow(text: tr("bankingTab.noTransactions"), systemImage: "arrow.left.arrow.right")
                }
                ForEach(transactions) { tx in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tx.label).font(.subheadline.weight(.semibold))
                            Text(tx.entryDate).font(.caption).foregroundStyle(Color.muted)
                        }
                        Spacer()
                        Text("\(tx.amount > 0 ? "+" : "")\(Fmt.num(tx.amount))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tx.amount < 0 ? Color.danger : Color.success)
                    }
                    .swipeActions {
                        Button(tr("bankingTab.remove"), role: .destructive) {
                            Task {
                                try? await API.shared.delete("/banking/accounts/\(account.id)/transactions/\(tx.id)")
                                await load()
                                onChange()
                            }
                        }
                    }
                }
            } header: {
                Text("\(tr("bankingTab.transactionsFor")) \(account.name)")
            }
        }
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showNew) {
            NavigationStack {
                BankTransactionForm(account: account) {
                    Task { await load() }
                    onChange()
                }
            }
        }
    }

    private func load() async {
        transactions = (try? await API.shared.get("/banking/accounts/\(account.id)/transactions")) ?? []
        let accounts: [BankAccount] = (try? await API.shared.get("/banking/accounts", query: ["country": account.country])) ?? []
        if let fresh = accounts.first(where: { $0.id == account.id }) { balance = fresh.balance }
    }
}

struct BankTransactionForm: View {
    let account: BankAccount
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label = ""
    @State private var amount = ""
    @State private var isWithdrawal = false
    @State private var date = Fmt.today()
    @State private var busy = false

    var body: some View {
        Form {
            Section {
                Picker("", selection: $isWithdrawal) {
                    Label(tr("banking.deposit"), systemImage: "arrow.down").tag(false)
                    Label(tr("banking.withdrawal"), systemImage: "arrow.up").tag(true)
                }
                .pickerStyle(.segmented)
                LabeledField(label: tr("bankingTab.label"), text: $label)
                LabeledField(label: "\(tr("bankingTab.amountCol")) (\(account.currency))", text: $amount, keyboard: .decimalPad)
                DateField(label: tr("bankingTab.date"), text: $date)
            } footer: {
                Text(tr("bankingTab.amount").capitalizedFirst)
            }
            Section {
                PrimaryButton(title: tr("bankingTab.addTransaction"), loading: busy) { Task { await submit() } }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(tr("bankingTab.newTransaction"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(tr("common.cancel")) { dismiss() } }
        }
    }

    private func submit() async {
        guard let text = label.nilIfBlank, let value = Fmt.parse(amount), value != 0 else { return }
        busy = true
        defer { busy = false }
        let signed = isWithdrawal ? -abs(value) : abs(value)
        do {
            let _: BankTransaction = try await API.shared.post(
                "/banking/accounts/\(account.id)/transactions",
                body: NewBankTransaction(accountId: account.id, label: text, amount: signed, entryDate: date)
            )
            toast(tr("bankingTab.txRecorded"))
            onSaved()
            dismiss()
        } catch {
            toast("\(tr("bankingTab.txFailed")) — \(error.localizedDescription)", error: true)
        }
    }
}
