import Charts
import SwiftUI

/// Analytics (src/features/stats/StatsPage.jsx), plus the user's own
/// custom charts (saved on the server, shared with the website).
struct StatsView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var summary = ClientSummary()
    @State private var country: Country?
    @State private var visaType = "all"
    // Accounting data per country, so switching the filter doesn't refetch.
    @State private var treasury: [Country: [TreasuryMonth]] = [:]
    @State private var invoiceTypes: [Country: [StatsRow]] = [:]
    @State private var accounts: [Country: [BankAccount]] = [:]
    @State private var payslips: [Payslip] = []
    @State private var charts: [StatsChart] = []
    @State private var showBuilder = false
    @State private var chartToRemove: StatsChart?

    private var selectedCountries: [Country] { country.map { [$0] } ?? Country.allCases }

    private var series: [(month: String, count: Int)] { summary.byMonth.map { ($0.month, $0.count) } }

    private var statusCounts: [(status: VisaStatus, count: Int)] {
        VisaStatus.allCases.map { status in (status, summary.count(status)) }
    }

    private var byCountry: [(name: String, value: Double, color: Color)] {
        Country.allCases.map { c in
            (c.label, Double(summary.count(c)), c == .tunisia ? Color.accentPurple : Color.accentOrange)
        }.filter { $0.value > 0 }
    }

    private var treasuryMonthly: [TreasuryMonth] {
        var merged: [String: TreasuryMonth] = [:]
        for c in selectedCountries {
            for row in treasury[c] ?? [] {
                var bucket = merged[row.month] ?? TreasuryMonth(month: row.month, spending: 0, gathering: 0)
                bucket.gathering += row.gathering
                bucket.spending += row.spending
                merged[row.month] = bucket
            }
        }
        return Array(merged.values.sorted { $0.month < $1.month }.suffix(6))
    }

    private func invoiceCount(_ docType: String) -> Int {
        selectedCountries.reduce(0) { total, c in
            total + Int((invoiceTypes[c] ?? []).first { $0.key == docType }?.value ?? 0)
        }
    }
    private var bankAccounts: [BankAccount] { selectedCountries.flatMap { accounts[$0] ?? [] } }

    private var payrollByPeriod: [(period: String, total: Double)] {
        var order: [String] = []
        var totals: [String: Double] = [:]
        for p in payslips {
            if totals[p.periodLabel] == nil { order.append(p.periodLabel) }
            totals[p.periodLabel, default: 0] += p.netToPay
        }
        return order.map { ($0, totals[$0] ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PageHeader(kicker: tr("statsPage.kicker"), title: tr("statsPage.title"))

                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("statsPage.filters")).font(.headline)
                    Picker(tr("statsPage.country"), selection: $country) {
                        Text(tr("common.allCountries")).tag(Country?.none)
                        ForEach(Country.allCases) { Text("\($0.flag) \($0.label)").tag(Optional($0)) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Text(tr("statsPage.visaType")).foregroundStyle(Color.muted)
                        Spacer()
                        Picker(tr("statsPage.visaType"), selection: $visaType) {
                            Text(tr("common.allTypes")).tag("all")
                            ForEach(VisaType.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                    }
                    Text("\(summary.total) \(tr("statsPage.clientsMatch"))")
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                }
                .card()

                chartCard(tr("statsPage.newClientsPerMonth"),
                          subtitle: "\(country?.label ?? tr("common.allCountries")) · \(visaType == "all" ? tr("statsPage.allVisaTypes") : (VisaType(rawValue: visaType)?.label ?? visaType))") {
                    if series.isEmpty {
                        EmptyRow(text: tr("statsPage.noClientData"), systemImage: "chart.line.uptrend.xyaxis")
                    } else {
                        Chart(series, id: \.month) { point in
                            LineMark(x: .value("Month", Fmt.shortMonth(point.month)), y: .value(tr("statsPage.newClients"), point.count))
                                .foregroundStyle(Color.accentPurple)
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Month", Fmt.shortMonth(point.month)), y: .value(tr("statsPage.newClients"), point.count))
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
                        DonutChart(slices: byCountry)
                    }
                }

                chartCard(tr("statsPage.facturesVsRecus")) {
                    let factures = invoiceCount("facture")
                    let recus = invoiceCount("recu")
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
                        BarList(items: bankAccounts.map {
                            BarList.Item(id: "\($0.id)", label: $0.name, value: $0.balance, color: .accentGreen,
                                         valueText: Fmt.money($0.balance, $0.currency))
                        })
                    }
                }

                chartCard(tr("statsPage.payrollCost")) {
                    if payrollByPeriod.isEmpty {
                        EmptyRow(text: tr("statsPage.noPayslipsYet"), systemImage: "banknote")
                    } else {
                        Chart(payrollByPeriod, id: \.period) { row in
                            BarMark(x: .value("Period", Fmt.shortMonth(row.period)), y: .value(tr("payroll.grossTotalCol"), row.total))
                                .foregroundStyle(Color.accentNavy)
                                .cornerRadius(6)
                        }
                        .frame(height: 200)
                    }
                }

                customChartsSection
            }
            .padding()
        }
        .background(Color.surface)
        .navigationTitle(tr("nav.stats"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showBuilder = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel(tr("customCharts.add"))
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .task(id: "\(country?.rawValue ?? "")|\(visaType)") { await loadSummary() }
        .sheet(isPresented: $showBuilder) {
            NavigationStack {
                ChartBuilderView(isAdmin: auth.isAdmin) { Task { await loadCharts() } }
            }
        }
        .confirmationDialog(tr("customCharts.removeConfirm"), isPresented: Binding(
            get: { chartToRemove != nil }, set: { if !$0 { chartToRemove = nil } }
        ), titleVisibility: .visible) {
            Button(tr("customCharts.remove"), role: .destructive) {
                if let chart = chartToRemove {
                    Task {
                        try? await API.shared.delete("/stats/charts/\(chart.id)")
                        await loadCharts()
                    }
                }
            }
        }
    }

    private var customChartsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("customCharts.title")).font(.title3.weight(.bold))
                    Text(tr("customCharts.subtitle")).font(.footnote).foregroundStyle(Color.muted)
                }
                Spacer()
            }
            .padding(.top, 12)

            ForEach(charts) { chart in
                CustomChartCard(chart: chart) { chartToRemove = chart }
            }

            if charts.isEmpty {
                Text(tr("customCharts.empty"))
                    .font(.subheadline)
                    .foregroundStyle(Color.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .card(padding: 20)
            }

            PrimaryButton(title: tr("customCharts.add"), systemImage: "plus") { showBuilder = true }
        }
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

    /// Client counts come from the server for the chosen country and visa type.
    private func loadSummary() async {
        var query: [String: String] = [:]
        if let country { query["country"] = country.rawValue }
        if visaType != "all" { query["visa_type"] = visaType }
        if let data: ClientSummary = try? await API.shared.get("/clients/summary", query: query) { summary = data }
    }

    private func loadCharts() async {
        charts = (try? await API.shared.get("/stats/charts")) ?? charts
    }

    private func load() async {
        await loadCharts()
        await loadSummary()

        // Treasury, banking, invoices and payroll are admin-only.
        guard auth.isAdmin else { return }
        for c in Country.allCases {
            let query = ["country": c.rawValue]
            if let t: TreasuryResponse = try? await API.shared.get("/treasury", query: query) { treasury[c] = t.history }
            if let list: [BankAccount] = try? await API.shared.get("/banking/accounts", query: query) { accounts[c] = list }
            var draft = StatsChartDraft()
            draft.source = "invoices"; draft.groupBy = "doc_type"; draft.country = c.rawValue
            if let rows = try? await ChartCatalog.rows(for: draft) { invoiceTypes[c] = rows }
        }
        payslips = (try? await API.shared.get("/payroll/payslips")) ?? payslips
    }
}

struct TreasuryBarChart: View {
    let data: [TreasuryMonth]
    var currency: String? = nil

    var body: some View {
        Chart {
            ForEach(data) { row in
                BarMark(x: .value("Month", Fmt.shortMonth(row.month)), y: .value("Amount", row.gathering))
                    .foregroundStyle(by: .value("Kind", tr("treasuryTab.gathering")))
                    .position(by: .value("Kind", tr("treasuryTab.gathering")))
                    .cornerRadius(4)
                BarMark(x: .value("Month", Fmt.shortMonth(row.month)), y: .value("Amount", row.spending))
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
