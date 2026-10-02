import Charts
import SwiftUI

/// What a custom chart can show — same as src/features/stats/customCharts.js
/// and SOURCES in backend/stats.py, which does the grouping.
enum ChartCatalog {
    struct Source {
        let id: String
        let admin: Bool
        let country: Bool
        let dated: Bool
        let dims: [String]
        let metrics: [String]
    }

    static let sources: [Source] = [
        Source(id: "clients", admin: false, country: true, dated: true,
               dims: ["visa_status", "visa_type", "category", "payment_state", "paiement_type", "currency",
                      "nationality", "country", "sex", "destination", "created_by", "month", "flight_month"],
               metrics: ["count", "prix_dossier", "reservation_amount"]),
        Source(id: "invoices", admin: true, country: true, dated: true,
               dims: ["doc_type", "country", "month", "client_name", "company_name", "service_type"],
               metrics: ["count", "amount_paid"]),
        Source(id: "treasury", admin: true, country: true, dated: true,
               dims: ["kind", "country", "month", "product_name", "recorded_by", "counterparty"],
               metrics: ["count", "price"]),
        Source(id: "bank_accounts", admin: true, country: true, dated: false,
               dims: ["name", "country", "currency"],
               metrics: ["count", "balance"]),
        Source(id: "payslips", admin: true, country: false, dated: true,
               dims: ["employee_name", "period_label", "month"],
               metrics: ["count", "net_total", "gross_total", "hours", "advances"]),
        Source(id: "employee_requests", admin: false, country: false, dated: true,
               dims: ["category", "status", "employee_name", "month"],
               metrics: ["count"]),
    ]

    static let chartTypes = ["bar", "hbar", "line", "pie"]
    static let periods = [3, 6, 12, 24]
    static let colors: [Color] = [
        .accentPurple, .accentOrange, .accentGreen, Color(hex: 0x3B82F6), .accentRed, Color(hex: 0x14B8A6),
        Color(hex: 0xEAB308), Color(hex: 0xEC4899), Color(hex: 0x6366F1), Color(hex: 0x0EA5E9), .accentNavy, .accentGray,
    ]

    static func source(_ id: String) -> Source { sources.first { $0.id == id } ?? sources[0] }
    static func sources(isAdmin: Bool) -> [Source] { sources.filter { isAdmin || !$0.admin } }

    static func sourceLabel(_ id: String) -> String { tr("customCharts.sources.\(id)") }
    static func dimLabel(_ id: String) -> String { tr("customCharts.dims.\(id)") }
    static func metricLabel(_ id: String) -> String { tr("customCharts.metrics.\(id)") }
    static func typeLabel(_ id: String) -> String { tr("customCharts.types.\(id)") }

    static func typeIcon(_ id: String) -> String {
        switch id {
        case "hbar": return "line.3.horizontal"
        case "line": return "chart.xyaxis.line"
        case "pie": return "chart.pie"
        default: return "chart.bar"
        }
    }

    static func periodLabel(_ months: Int?) -> String {
        guard let months else { return tr("customCharts.allTime") }
        return tr("customCharts.lastMonths").replacingOccurrences(of: "{n}", with: "\(months)")
    }

    /// Keep a draft valid for its data source (fields differ per source).
    static func fit(_ draft: inout StatsChartDraft) {
        let source = source(draft.source)
        if !source.dims.contains(draft.groupBy) { draft.groupBy = source.dims[0] }
        if !source.metrics.contains(draft.metric) { draft.metric = "count" }
        if !source.country { draft.country = nil }
        if !source.dated { draft.months = nil }
    }

    /// Translated label for one group (bar / slice) of a chart.
    static func groupLabel(source: String, dim: String, key: String?) -> String {
        guard let key, !key.isEmpty else { return tr("customCharts.notSet") }
        func lookup(_ namespace: String, _ id: String) -> String {
            let fullKey = "\(namespace).\(id)"
            let label = tr(fullKey)
            return label == fullKey ? key : label
        }
        switch dim {
        case "visa_status": return lookup("visa", key)
        case "visa_type": return lookup("visaType", key)
        case "category":
            if source == "employee_requests" {
                return EmployeeRequestsView.Category(rawValue: key)?.label ?? key
            }
            return lookup("category", key)
        case "payment_state": return lookup("payment", key)
        case "paiement_type": return lookup("paymentMethod", key)
        case "currency": return lookup("currencies", key)
        case "country": return Country.label(for: key)
        case "doc_type": return key == "recu" ? tr("invoicesTab.recu") : key == "facture" ? tr("invoicesTab.facture") : key
        case "kind": return key == "gathering" ? tr("treasuryTab.gathering") : key == "spending" ? tr("treasuryTab.spending") : key
        case "status": return lookup("status", key)
        case "month", "flight_month", "period_label": return Fmt.shortMonth(key)
        default: return key
        }
    }

    static func rows(for draft: StatsChartDraft) async throws -> [StatsRow] {
        try await API.shared.post("/stats/query", body: draft)
    }
}

/// Draws a custom chart's rows as its chart type.
struct CustomChartView: View {
    let chart: StatsChartDraft
    let rows: [StatsRow]

    private struct Point: Identifiable {
        let id: Int
        let label: String
        let value: Double
        let color: Color
    }

    private var points: [Point] {
        rows.enumerated().map { index, row in
            Point(id: index,
                  label: ChartCatalog.groupLabel(source: chart.source, dim: chart.groupBy, key: row.key),
                  value: row.value,
                  color: ChartCatalog.colors[index % ChartCatalog.colors.count])
        }
    }

    var body: some View {
        if rows.isEmpty {
            EmptyRow(text: tr("customCharts.noData"), systemImage: "chart.bar.xaxis")
        } else {
            switch chart.chartType {
            case "pie":
                DonutChart(slices: points.map { ($0.label, $0.value, $0.color) })
            case "hbar":
                BarList(items: points.map { BarList.Item(id: "\($0.id)", label: $0.label, value: $0.value, color: $0.color) })
            case "line":
                Chart(points) { point in
                    LineMark(x: .value(ChartCatalog.dimLabel(chart.groupBy), point.label),
                             y: .value(ChartCatalog.metricLabel(chart.metric), point.value))
                        .foregroundStyle(Color.accentPurple)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value(ChartCatalog.dimLabel(chart.groupBy), point.label),
                              y: .value(ChartCatalog.metricLabel(chart.metric), point.value))
                        .foregroundStyle(Color.accentPurple)
                }
                .frame(height: 220)
            default:
                Chart(points) { point in
                    BarMark(x: .value(ChartCatalog.dimLabel(chart.groupBy), point.label),
                            y: .value(ChartCatalog.metricLabel(chart.metric), point.value))
                        .foregroundStyle(point.color)
                        .cornerRadius(5)
                }
                .frame(height: 220)
            }
        }
    }
}

/// One saved chart on the Stats screen; loads its own data.
struct CustomChartCard: View {
    let chart: StatsChart
    let onRemove: () -> Void

    @State private var rows: [StatsRow]?
    @State private var failed = false

    private var subtitle: String {
        [
            ChartCatalog.dimLabel(chart.groupBy),
            ChartCatalog.sourceLabel(chart.source),
            ChartCatalog.metricLabel(chart.metric),
            chart.country.flatMap(Country.init(rawValue:))?.label,
            ChartCatalog.periodLabel(chart.months),
        ].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chart.title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(Color.muted)
                }
                Spacer()
                Menu {
                    Button(tr("customCharts.remove"), systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(Color.muted)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(tr("customCharts.remove"))
            }
            if failed {
                Text(tr("customCharts.loadFailed")).font(.footnote).foregroundStyle(Color.muted)
            } else if let rows {
                CustomChartView(chart: StatsChartDraft(chart), rows: rows)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .card()
        .contextMenu {
            Button(tr("customCharts.remove"), systemImage: "trash", role: .destructive, action: onRemove)
        }
        .task(id: chart.id) {
            do {
                rows = try await ChartCatalog.rows(for: StatsChartDraft(chart))
            } catch {
                failed = true
            }
        }
    }
}

/// Define a custom chart with a live preview, then save it to the account
/// (it then also shows on the website).
struct ChartBuilderView: View {
    let isAdmin: Bool
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = StatsChartDraft()
    @State private var rows: [StatsRow]?
    @State private var saving = false

    private var source: ChartCatalog.Source { ChartCatalog.source(draft.source) }

    /// Changes only when the data to plot changes (not the title or type).
    private var queryKey: String {
        "\(draft.source)|\(draft.groupBy)|\(draft.metric)|\(draft.country ?? "")|\(draft.months ?? 0)"
    }

    var body: some View {
        Form {
            Section {
                TextField(tr("customCharts.titlePlaceholder"), text: $draft.title)
            } header: {
                Text(tr("customCharts.chartTitle"))
            }

            Section {
                Picker(tr("customCharts.source"), selection: binding(\.source)) {
                    ForEach(ChartCatalog.sources(isAdmin: isAdmin), id: \.id) { Text(ChartCatalog.sourceLabel($0.id)).tag($0.id) }
                }
                Picker(tr("customCharts.groupBy"), selection: binding(\.groupBy)) {
                    ForEach(source.dims, id: \.self) { Text(ChartCatalog.dimLabel($0)).tag($0) }
                }
                Picker(tr("customCharts.metric"), selection: binding(\.metric)) {
                    ForEach(source.metrics, id: \.self) { Text(ChartCatalog.metricLabel($0)).tag($0) }
                }
                if source.country {
                    Picker(tr("customCharts.country"), selection: $draft.country) {
                        Text(tr("common.allCountries")).tag(String?.none)
                        ForEach(Country.allCases) { Text("\($0.flag) \($0.label)").tag(Optional($0.rawValue)) }
                    }
                }
                if source.dated {
                    Picker(tr("customCharts.period"), selection: $draft.months) {
                        Text(ChartCatalog.periodLabel(nil)).tag(Int?.none)
                        ForEach(ChartCatalog.periods, id: \.self) { Text(ChartCatalog.periodLabel($0)).tag(Optional($0)) }
                    }
                }
            }

            Section(tr("customCharts.chartType")) {
                IconTabPicker(items: ChartCatalog.chartTypes.map {
                    .init(value: $0, label: ChartCatalog.typeLabel($0), systemImage: ChartCatalog.typeIcon($0))
                }, selection: $draft.chartType)
                .listRowInsets(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 6))
                .listRowBackground(Color.clear)
            }

            Section(tr("customCharts.preview")) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(draft.title.nilIfBlank ?? tr("customCharts.titlePlaceholder"))
                        .font(.headline)
                        .foregroundStyle(draft.title.nilIfBlank == nil ? Color.muted : Color.ink)
                    if let rows {
                        CustomChartView(chart: draft, rows: rows)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle(tr("customCharts.newChart"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(tr("common.cancel")) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(tr("common.save")) { Task { await save() } }
                    .disabled(saving)
            }
        }
        .task(id: queryKey) {
            rows = nil
            try? await Task.sleep(for: .milliseconds(250)) // let quick changes settle
            guard !Task.isCancelled else { return }
            rows = (try? await ChartCatalog.rows(for: draft)) ?? []
        }
    }

    /// Binding that re-fits the draft after a source / field change.
    private func binding(_ keyPath: WritableKeyPath<StatsChartDraft, String>) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] }, set: { value in
            draft[keyPath: keyPath] = value
            ChartCatalog.fit(&draft)
        })
    }

    private func save() async {
        guard let title = draft.title.nilIfBlank else {
            toast(tr("customCharts.titleRequired"), error: true)
            return
        }
        saving = true
        defer { saving = false }
        var body = draft
        body.title = title
        do {
            let _: StatsChart = try await API.shared.post("/stats/charts", body: body)
            toast(tr("customCharts.saved"))
            onSaved()
            dismiss()
        } catch {
            toast("\(tr("customCharts.saveFailed")) — \(error.localizedDescription)", error: true)
        }
    }
}
