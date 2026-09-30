import SwiftUI
import UniformTypeIdentifiers

/// Fiche de paie (src/features/payroll/PayrollPage.jsx): upload an Excel
/// pointage, set each employee's hourly rate, generate PDF payslips.
struct PayrollView: View {
    struct Row: Identifiable {
        let id = UUID()
        let employeeName: String
        let hours: Double
        var rate = ""
    }

    @StateObject private var previewer = FilePreviewer()
    @State private var rows: [Row] = []
    @State private var period = Fmt.currentPeriodLabel()
    @State private var history: [Payslip] = []
    @State private var uploading = false
    @State private var busyRow: UUID?
    @State private var showImporter = false
    @State private var toRemove: Payslip?

    private static let excelTypes: [UTType] = [
        UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "xls"), .spreadsheet,
    ].compactMap { $0 }

    var body: some View {
        List {
            Section {
                Button { showImporter = true } label: {
                    HStack {
                        Label(tr("payroll.uploadPointage"), systemImage: "tablecells.badge.ellipsis")
                        if uploading { Spacer(); ProgressView() }
                    }
                }
                .disabled(uploading)
                LabeledField(label: tr("payroll.payPeriod"), text: $period)
            } footer: {
                Text("\(tr("payroll.columnsHint")) .xlsx")
            }

            if !rows.isEmpty {
                Section(tr("payroll.employeeCol")) {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(row.employeeName).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(Fmt.num(row.hours)) \(tr("payroll.hoursUnit"))").foregroundStyle(Color.muted)
                            }
                            HStack(spacing: 10) {
                                TextField(tr("payroll.hourlyRateCol"), text: $row.rate)
                                    .keyboardType(.decimalPad)
                                    .textFieldStyle(.roundedBorder)
                                Button {
                                    Task { await generate(row) }
                                } label: {
                                    if busyRow == row.id {
                                        ProgressView()
                                    } else {
                                        Text(tr("payroll.generate")).font(.caption.weight(.semibold))
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(busyRow != nil)
                            }
                            if let rate = Fmt.parse(row.rate) {
                                Text("≈ \(Fmt.money(row.hours * rate, "TND"))").font(.caption).foregroundStyle(Color.muted)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section(tr("payroll.generatedPayslips")) {
                if history.isEmpty {
                    EmptyRow(text: tr("payroll.noPayslips"), systemImage: "doc.plaintext")
                }
                ForEach(history) { payslip in
                    Button {
                        Task { await open(payslip) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(payslip.employeeName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                                Text("\(payslip.periodLabel) · \(Fmt.num(payslip.hours)) \(tr("payroll.hoursUnit"))").font(.caption).foregroundStyle(Color.muted)
                            }
                            Spacer()
                            if previewer.loadingPath == pdfPath(payslip) {
                                ProgressView()
                            } else {
                                Text(Fmt.money(payslip.grossTotal, payslip.currency))
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                                Image(systemName: "arrow.down.doc").foregroundStyle(Color.brand)
                            }
                        }
                    }
                    .swipeActions {
                        Button(tr("payroll.remove"), role: .destructive) { toRemove = payslip }
                    }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(tr("payroll.title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadHistory() }
        .task { await loadHistory() }
        .filePreview(previewer)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.excelTypes) { result in
            if case .success(let url) = result, let file = UploadFile.from(url: url) {
                Task { await parse(file) }
            }
        }
        .confirmationDialog(tr("payroll.removeConfirm"), isPresented: Binding(
            get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }
        ), titleVisibility: .visible) {
            Button(tr("payroll.remove"), role: .destructive) {
                if let payslip = toRemove {
                    Task {
                        try? await API.shared.delete("/payroll/payslips/\(payslip.id)")
                        await loadHistory()
                    }
                }
            }
        }
    }

    private func pdfPath(_ payslip: Payslip) -> String { "/payroll/payslips/\(payslip.id)/pdf" }

    private func open(_ payslip: Payslip) async {
        await previewer.open(pdfPath(payslip), filename: "payslip-\(payslip.id).pdf", failure: tr("payroll.downloadFailed"))
    }

    private func loadHistory() async {
        history = (try? await API.shared.get("/payroll/payslips")) ?? []
    }

    private func parse(_ file: UploadFile) async {
        uploading = true
        defer { uploading = false }
        do {
            let parsed: [PointageRow] = try await API.shared.upload("/payroll/parse-pointage", field: "file", files: [file])
            rows = parsed.map { Row(employeeName: $0.employeeName, hours: $0.hours) }
            toast("\(tr("payroll.parsed")) \(parsed.count) \(tr("payroll.employeesWord"))")
        } catch {
            toast("\(tr("payroll.readFailed")) — \(error.localizedDescription)", error: true)
        }
    }

    private func generate(_ row: Row) async {
        guard let rate = Fmt.parse(row.rate) else {
            toast(tr("payroll.enterRate"), error: true)
            return
        }
        busyRow = row.id
        defer { busyRow = nil }
        do {
            let payslip: Payslip = try await API.shared.post("/payroll/payslips", body: NewPayslip(
                employeeName: row.employeeName, periodLabel: period, hours: row.hours, hourlyRate: rate, currency: "TND"
            ))
            toast(tr("payroll.generated"))
            await loadHistory()
            await open(payslip)
        } catch {
            toast("\(tr("payroll.generateFailed")) — \(error.localizedDescription)", error: true)
        }
    }
}
