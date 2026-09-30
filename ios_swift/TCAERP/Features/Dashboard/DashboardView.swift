import Charts
import SwiftUI

/// Overview (src/features/dashboard/DashboardPage.jsx).
struct DashboardView: View {
    @State private var clients: [Client] = []
    @State private var treasuryMonthly: [TreasuryMonth] = []
    @State private var monthNet: Double = 0
    @State private var bankTotal: Double = 0
    @State private var invoiceCount = 0

    private var statusCounts: [(status: VisaStatus, count: Int)] {
        VisaStatus.allCases.map { status in
            (status, clients.filter { $0.visa == status }.count)
        }
    }

    private func count(_ status: VisaStatus) -> Int {
        statusCounts.first { $0.status == status }?.count ?? 0
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PageHeader(kicker: tr("dashboard.kicker"), title: tr("dashboard.title"))

                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("dashboard.treasuryNet").uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(Fmt.num(monthNet))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(tr("dashboard.treasuryNetBody").replacingOccurrences(of: "{amount}", with: Fmt.num(bankTotal)))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.cardInk, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatTile(label: tr("dashboard.totalClients"), value: "\(clients.count)",
                             note: tr("dashboard.inDatabase"), accent: .accentPurple)
                    StatTile(label: tr("dashboard.inProgress"), value: "\(clients.filter { $0.visa.isInProgress }.count)",
                             note: tr("dashboard.awaitingDecision"), accent: .accentOrange)
                    StatTile(label: tr("dashboard.missingDocs"), value: "\(count(.missingDocuments))",
                             note: tr("dashboard.needFollowUp"), accent: .accentRed)
                    StatTile(label: tr("dashboard.invoicesReceipts"), value: "\(invoiceCount)",
                             note: tr("dashboard.issuedToDate"), accent: .accentGreen)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(tr("dashboard.treasuryChart")).font(.headline)
                        Spacer()
                        Text(tr("dashboard.last6Months")).font(.caption).foregroundStyle(Color.muted)
                    }
                    if treasuryMonthly.isEmpty {
                        EmptyRow(text: tr("statsTab.noHistory"), systemImage: "chart.xyaxis.line")
                    } else {
                        TreasuryAreaChart(data: treasuryMonthly)
                            .frame(height: 220)
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 12) {
                    Text(tr("dashboard.byVisaStatus")).font(.headline)
                    VisaStatusChart(counts: statusCounts)
                    Text("\(clients.filter(\.isAlert).count) \(tr("dashboard.needAlertFollowUp"))")
                        .font(.footnote)
                        .foregroundStyle(Color.muted)
                }
                .card()
            }
            .padding()
        }
        .background(Color.surface)
        .navigationTitle(tr("nav.dashboard"))
        .navigationBarTitleDisplayMode(.inline)
        .rootToolbar()
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        if let data: [Client] = try? await API.shared.get("/clients") { clients = data }

        // Treasury/banking/invoices are admin-only; agents just see zeros.
        var merged: [String: TreasuryMonth] = [:]
        var net: Double = 0
        var bank: Double = 0
        var invoices = 0
        for country in Country.allCases {
            let query = ["country": country.rawValue]
            if let t: TreasuryResponse = try? await API.shared.get("/treasury", query: query) {
                net += t.currentMonth.net
                for row in t.history {
                    var bucket = merged[row.month] ?? TreasuryMonth(month: row.month, spending: 0, gathering: 0)
                    bucket.gathering += row.gathering
                    bucket.spending += row.spending
                    merged[row.month] = bucket
                }
            }
            if let accounts: [BankAccount] = try? await API.shared.get("/banking/accounts", query: query) {
                bank += accounts.reduce(0) { $0 + $1.balance }
            }
            if let list: [Invoice] = try? await API.shared.get("/invoices", query: query) {
                invoices += list.count
            }
        }
        monthNet = net
        bankTotal = bank
        invoiceCount = invoices
        treasuryMonthly = Array(merged.values.sorted { $0.month < $1.month }.suffix(6))
    }
}

struct TreasuryAreaChart: View {
    let data: [TreasuryMonth]

    var body: some View {
        Chart {
            ForEach(data) { row in
                AreaMark(x: .value("Month", row.month), y: .value(tr("dashboard.gathering"), row.gathering))
                    .foregroundStyle(Color.accentPurple.opacity(0.18))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Month", row.month), y: .value(tr("dashboard.gathering"), row.gathering),
                         series: .value("Series", "gathering"))
                    .foregroundStyle(Color.accentPurple)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Month", row.month), y: .value(tr("dashboard.spending"), row.spending),
                         series: .value("Series", "spending"))
                    .foregroundStyle(Color.accentOrange)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
            }
        }
        .chartLegend(.hidden)
        .overlay(alignment: .topLeading) {
            HStack(spacing: 12) {
                LegendDot(color: .accentPurple, text: tr("dashboard.gathering"))
                LegendDot(color: .accentOrange, text: tr("dashboard.spending"))
            }
            .offset(y: -4)
        }
        .padding(.top, 14)
    }
}

struct VisaStatusChart: View {
    let counts: [(status: VisaStatus, count: Int)]

    var body: some View {
        Chart(counts, id: \.status) { item in
            BarMark(x: .value("Clients", item.count), y: .value("Status", item.status.label))
                .foregroundStyle(item.status.color)
                .cornerRadius(6)
                .annotation(position: .trailing) {
                    Text("\(item.count)").font(.caption2).foregroundStyle(Color.muted)
                }
        }
        .chartXAxis(.hidden)
        .frame(height: CGFloat(counts.count) * 26)
    }
}

struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(Color.muted)
        }
    }
}
