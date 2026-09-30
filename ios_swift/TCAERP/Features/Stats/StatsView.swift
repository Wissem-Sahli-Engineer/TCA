import Charts
import SwiftUI

/// Analytics (src/features/stats/StatsPage.jsx).
struct StatsView: View {
    @State private var clients: [Client] = []
    @State private var country = "all"
    @State private var visaType = "all"
    @State private var treasuryMonthly: [TreasuryMonth] = []
    @State private var factures = 0
    @State private var recus = 0
    @State private var bankAccounts: [BankAccount] = []
    @State private var payrollByPeriod: [(period: String, total: Double)] = []

    private var countries: [String] { Array(Set(clients.compactMap(\.country).filter { !$0.isEmpty })).sorted() }
    private var visaTypes: [String] { Array(Set(clients.compactMap(\.visaType).filter { !$0.isEmpty })).sorted() }

    private var filtered: [Client] {
        clients.filter {
            (country == "all" || $0.country == country) && (visaType == "all" || $0.visaType == visaType)
        }
    }

    private var series: [(month: String, count: Int)] {
        var byMonth: [String: Int] = [:]
        for client in filtered {
            guard let created = client.createdAt, created.count >= 7 else { continue }
            byMonth[String(created.prefix(7)), default: 0] += 1
        }
        return byMonth.keys.sorted().map { ($0, byMonth[$0] ?? 0) }
    }

    private var statusCounts: [(status: VisaStatus, count: Int)] {
        VisaStatus.allCases.map { status in
            (status, clients.filter { $0.visa == status }.count)
        }
    }

    private var byCountry: [(name: String, value: Int, color: Color)] {
        [
            ("tunisia", Color.accentPurple),
            ("libya", Color.accentOrange),
        ].map { name, color in
            (name, clients.filter { $0.country?.lowercased() == name }.count, color)
        }.filter { $0.value > 0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PageHeader(kicker: tr("statsPage.kicker"), title: tr("statsPage.title"))

                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("statsPage.filters")).font(.headline)
                    HStack {
                        Text(tr("statsPage.country")).foregroundStyle(Color.muted)
                        Spacer()
                        Picker(tr("statsPage.country"), selection: $country) {
                            Text(tr("common.allCountries")).tag("all")
                            ForEach(countries, id: \.self) { Text(Country.label(for: $0)).tag($0) }
                        }
                    }
                    HStack {
                        Text(tr("statsPage.visaType")).foregroundStyle(Color.muted)
                        Spacer()
                        Picker(tr("statsPage.visaType"), selection: $visaType) {
                            Text(tr("common.allTypes")).tag("all")
                            ForEach(visaTypes, id: \.self) { Text(VisaType(rawValue: $0)?.label ?? $0).tag($0) }
                        }
                    }
                    Text("\(filtered.count) \(tr("statsPage.clientsMatch"))")
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                }
                .card()

                chartCard(tr("statsPage.newClientsPerMonth"),
                          subtitle: "\(country == "all" ? tr("common.allCountries") : Country.label(for: country)) · \(visaType == "all" ? tr("statsPage.allVisaTypes") : (VisaType(rawValue: visaType)?.label ?? visaType))") {
                    if series.isEmpty {
                        EmptyRow(text: tr("statsPage.noClientData"), systemImage: "chart.line.uptrend.xyaxis")
                    } else {
                        Chart(series, id: \.month) { point in
                            LineMark(x: .value("Month", point.month), y: .value(tr("statsPage.newClients"), point.count))
                                .foregroundStyle(Color.accentPurple)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Month", point.month), y: .value(tr("statsPage.newClients"), point.count))
                                .foregroundStyle(Color.accentPurple)
                        }
                        .frame(height: 220)
                    }
                }

                chartCard(tr("statsPage.visaStatusChart")) {
                    VisaStatusChart(counts: statusCounts)
                }

                chartCard(tr("statsPage.byCountry")) {
                    if byCountry.isEmpty {
                        EmptyRow(text: tr("statsPage.noDataYet"), systemImage: "chart.pie")
                    } else {
                        DonutChart(slices: byCountry.map { (Country.label(for: $0.name), Double($0.value), $0.color) })
                    }
                }

                chartCard(tr("statsPage.facturesVsRecus")) {
                    if factures + recus == 0 {
                        EmptyRow(text: tr("statsPage.noInvoicesYet"), systemImage: "chart.pie")
                    } else {
                        DonutChart(slices: [
                            (tr("statsPage.factures"), Double(factures), .accentPurple),
                            (tr("statsPage.recus"), Double(recus), .accentOrange),
                        ])
                    }
                }

                chartCard(tr("statsPage.treasuryChart")) {
                    if treasuryMonthly.isEmpty {
                        EmptyRow(text: tr("statsTab.noHistory"), systemImage: "chart.bar")
                    } else {
                        TreasuryBarChart(data: treasuryMonthly).frame(height: 220)
                    }
                }

                chartCard(tr("statsPage.bankBalances")) {
                    if bankAccounts.isEmpty {
                        EmptyRow(text: tr("statsPage.noAccountsYet"), systemImage: "building.columns")
                    } else {
                        Chart(bankAccounts) { account in
                            BarMark(x: .value("Balance", account.balance), y: .value("Account", account.name))
                                .foregroundStyle(Color.accentGreen)
                                .cornerRadius(6)
                                .annotation(position: .trailing) {
                                    Text(Fmt.money(account.balance, account.currency))
                                        .font(.caption2).foregroundStyle(Color.muted)
                                }
                        }
                        .chartXAxis(.hidden)
                        .frame(height: max(120, CGFloat(bankAccounts.count) * 44))
                    }
                }

                chartCard(tr("statsPage.payrollCost")) {
                    if payrollByPeriod.isEmpty {
                        EmptyRow(text: tr("statsPage.noPayslipsYet"), systemImage: "banknote")
                    } else {
                        Chart(payrollByPeriod, id: \.period) { row in
                            BarMark(x: .value("Period", row.period), y: .value("Total", row.total))
                                .foregroundStyle(Color.accentNavy)
                                .cornerRadius(6)
                        }
                        .frame(height: 200)
                    }
                }
            }
            .padding()
        }
        .background(Color.surface)
        .navigationTitle(tr("nav.stats"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    @ViewBuilder
    private func chartCard<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Color.muted)
                }
            }
            content()
        }
        .card()
    }

    private func load() async {
        if let data: [Client] = try? await API.shared.get("/clients") { clients = data }

        var merged: [String: TreasuryMonth] = [:]
        var accounts: [BankAccount] = []
        var fac = 0, rec = 0
        for country in Country.allCases {
            let query = ["country": country.rawValue]
            if let t: TreasuryResponse = try? await API.shared.get("/treasury", query: query) {
                for row in t.history {
                    var bucket = merged[row.month] ?? TreasuryMonth(month: row.month, spending: 0, gathering: 0)
                    bucket.gathering += row.gathering
                    bucket.spending += row.spending
                    merged[row.month] = bucket
                }
            }
            if let list: [BankAccount] = try? await API.shared.get("/banking/accounts", query: query) {
                accounts += list
            }
            if let invoices: [Invoice] = try? await API.shared.get("/invoices", query: query) {
                fac += invoices.filter { $0.docType == "facture" }.count
                rec += invoices.filter { $0.docType == "recu" }.count
            }
        }
        treasuryMonthly = Array(merged.values.sorted { $0.month < $1.month }.suffix(6))
        bankAccounts = accounts
        factures = fac
        recus = rec

        if let payslips: [Payslip] = try? await API.shared.get("/payroll/payslips") {
            var order: [String] = []
            var totals: [String: Double] = [:]
            for p in payslips {
                if totals[p.periodLabel] == nil { order.append(p.periodLabel) }
                totals[p.periodLabel, default: 0] += p.grossTotal
            }
            payrollByPeriod = order.map { ($0, totals[$0] ?? 0) }
        }
    }
}

struct TreasuryBarChart: View {
    let data: [TreasuryMonth]
    var currency: String? = nil

    var body: some View {
        Chart {
            ForEach(data) { row in
                BarMark(x: .value("Month", row.month), y: .value("Amount", row.gathering))
                    .foregroundStyle(by: .value("Kind", tr("treasuryTab.gathering")))
                    .position(by: .value("Kind", tr("treasuryTab.gathering")))
                    .cornerRadius(4)
                BarMark(x: .value("Month", row.month), y: .value("Amount", row.spending))
                    .foregroundStyle(by: .value("Kind", tr("treasuryTab.spending")))
                    .position(by: .value("Kind", tr("treasuryTab.spending")))
                    .cornerRadius(4)
            }
        }
        .chartForegroundStyleScale([
            tr("treasuryTab.gathering"): Color.accentPurple,
            tr("treasuryTab.spending"): Color.accentOrange,
        ])
        .chartLegend(position: .top, alignment: .leading)
    }
}

struct DonutChart: View {
    let slices: [(name: String, value: Double, color: Color)]

    var body: some View {
        HStack(spacing: 20) {
            Chart(slices, id: \.name) { slice in
                SectorMark(angle: .value("Value", slice.value), innerRadius: .ratio(0.6), angularInset: 1.5)
                    .foregroundStyle(slice.color)
                    .cornerRadius(4)
            }
            .frame(width: 140, height: 140)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(slices, id: \.name) { slice in
                    HStack(spacing: 8) {
                        Circle().fill(slice.color).frame(width: 10, height: 10)
                        Text(slice.name).font(.subheadline)
                        Spacer()
                        Text(Fmt.num(slice.value)).font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }
}
