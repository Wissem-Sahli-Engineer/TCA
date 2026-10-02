import SwiftUI
import UniformTypeIdentifiers

/// Fiche de paie (src/features/payroll/PayrollPage.jsx): import the ZKTeco
/// K40 time-clock export, set the hourly rate and advances, and generate
/// the Arabic payslip PDF (base, +25% overtime, +50% weekend, +100% holiday).
struct PayrollView: View {
    // Same defaults as the web page and paie_app.html.
    private static let defaultCompanyName = "شركة تونس للإستشارات والمساعدة"
    private static let defaultCompanyAddress = "عدد 85 شارع فلسطين عمارة القدس الطابق الثاني مكتب رقم 3 تونس، 1010"
    private static let defaultCompanyContact = "info@tunis-consulting.com — +216 29 190 039 | +216 28 846 888"

    private static let excelTypes: [UTType] = [
        UTType(filenameExtension: "xls"), UTType(filenameExtension: "xlsx"), .spreadsheet,
    ].compactMap { $0 }

    @StateObject private var previewer = FilePreviewer()
    @State private var fileName = ""
    @State private var employees: [PointageEmployee] = []
    @State private var selectedID: String?
    @State private var rate = ""
    @State private var advances = "0"
    @State private var pause = "60"
    @State private var m25 = "25"
    @State private var m50 = "50"
    @State private var m100 = "100"
    @State private var companyName = Self.defaultCompanyName
    @State private var companyAddress = Self.defaultCompanyAddress
    @State private var companyContact = Self.defaultCompanyContact
    @State private var showAdvanced = false
    @State private var uploading = false
    @State private var busy = false
    @State private var showImporter = false
    @State private var current: Payslip?
    @State private var currentPDF: URL?
    @State private var history: [Payslip] = []
    @State private var toRemove: Payslip?

    private var selected: PointageEmployee? {
        employees.first { $0.id == selectedID } ?? employees.first
    }

    private var rateValue: Double { Fmt.parse(rate) ?? 0 }

    var body: some View {
        List {
            Section {
                Button { showImporter = true } label: {
                    HStack {
                        Label(uploading ? tr("payroll.reading") : tr("payroll.uploadPointage"), systemImage: "tablecells.badge.ellipsis")
                        if uploading { Spacer(); ProgressView() }
                    }
                }
                .disabled(uploading)
                if !fileName.isEmpty {
                    Label("\(fileName) — \(employees.count) \(tr("payroll.fileLoaded")) \(selected?.days ?? 0) \(tr("payroll.daysWord"))",
                          systemImage: "checkmark.circle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.success)
                }
                if employees.count > 1 {
                    Picker(tr("payroll.employee"), selection: Binding(get: { selected?.id }, set: { selectedID = $0 })) {
                        ForEach(employees) { employee in
                            Text("\(employee.employeeName) (\(employee.matricule))").tag(Optional(employee.id))
                        }
                    }
                }
            } header: {
                Text(tr("payroll.step1"))
            } footer: {
                Text(tr("payroll.columnsHint"))
            }

            Section(tr("payroll.step2")) {
                LabeledField(label: tr("payroll.baseRate"), text: $rate, placeholder: "5.769", keyboard: .decimalPad)
                LabeledField(label: tr("payroll.advances"), text: $advances, keyboard: .decimalPad)
                DisclosureGroup(tr("payroll.advanced"), isExpanded: $showAdvanced) {
                    LabeledField(label: tr("payroll.pause"), text: $pause, keyboard: .numberPad)
                    LabeledField(label: tr("payroll.m25"), text: $m25, keyboard: .decimalPad)
                    LabeledField(label: tr("payroll.m50"), text: $m50, keyboard: .decimalPad)
                    LabeledField(label: tr("payroll.m100"), text: $m100, keyboard: .decimalPad)
                    LabeledField(label: tr("payroll.company"), text: $companyName)
                        .environment(\.layoutDirection, .rightToLeft)
                    LabeledField(label: tr("payroll.address"), text: $companyAddress)
                        .environment(\.layoutDirection, .rightToLeft)
                    LabeledField(label: tr("payroll.contact"), text: $companyContact, keyboard: .emailAddress, autocapitalize: .never)
                        .environment(\.layoutDirection, .leftToRight)
                }
            }

            Section {
                PrimaryButton(title: tr("payroll.generate"), systemImage: "doc.badge.gearshape", loading: busy) {
                    Task { await generate() }
                }
                .disabled(selected == nil || rateValue <= 0)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text(tr("payroll.formula"))
            }

            if let current {
                Section("\(current.employeeName) · \(current.periodLabel)") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        StatTile(label: tr("payroll.daysWorked"), value: current.details?.jours.map(String.init) ?? "—", accent: .accentPurple)
                        StatTile(label: tr("payroll.absences"), value: current.details?.abs.map(String.init) ?? "—", accent: .accentRed)
                        StatTile(label: overtimeLabel(current), value: current.details?.supHm ?? "—", accent: .accentOrange)
                        netTile(current)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)

                    Group {
                        if let currentPDF {
                            PDFPreview(url: currentPDF)
                        } else {
                            ProgressView(tr("common.loading")).frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(height: 460)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

                    Button {
                        if let currentPDF { previewer.url = currentPDF }
                    } label: {
                        Label(tr("payroll.downloadPdf"), systemImage: "square.and.arrow.up")
                    }
                    .disabled(currentPDF == nil)
                }
            } else {
                Section {
                    VStack(spacing: 8) {
                        Text("🧾").font(.system(size: 40))
                        Text(tr("payroll.emptyTitle")).font(.headline)
                        Text(tr("payroll.emptyText"))
                            .font(.subheadline)
                            .foregroundStyle(Color.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
            }

            Section(tr("payroll.generatedPayslips")) {
                if history.isEmpty {
                    EmptyRow(text: tr("payroll.noPayslips"), systemImage: "doc.plaintext")
                }
                ForEach(history) { payslip in
                    Button {
                        Task { await show(payslip) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(payslip.employeeName).font(.subheadline.weight(.semibold)).foregroundStyle(Color.ink)
                                Text("\(payslip.periodLabel) · \(Fmt.num(payslip.hours)) \(tr("payroll.hoursUnit"))")
                                    .font(.caption).foregroundStyle(Color.muted)
                            }
                            Spacer()
                            Text(Fmt.money(payslip.netToPay, payslip.currency))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.ink)
                            Image(systemName: "chevron.forward").font(.caption).foregroundStyle(Color.muted)
                        }
                    }
                    .listRowBackground(current?.id == payslip.id ? Color.brandWash : nil)
                    .swipeActions {
                        Button { toRemove = payslip } label: {
                            Label(tr("payroll.remove"), systemImage: "trash")
                        }
                        .tint(.red)
                    }
                    .contextMenu {
                        Button(tr("payroll.remove"), systemImage: "trash", role: .destructive) { toRemove = payslip }
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
                if let payslip = toRemove { Task { await remove(payslip) } }
            }
        }
    }

    private func overtimeLabel(_ payslip: Payslip) -> String {
        guard let m25 = payslip.details?.m25 else { return tr("payroll.overtime") }
        return "\(tr("payroll.overtime")) +\(Fmt.num(m25))%"
    }

    private func netTile(_ payslip: Payslip) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Capsule().fill(Color.white.opacity(0.6)).frame(width: 28, height: 4)
            Text(tr("payroll.netToPay").uppercased())
                .font(.caption2.weight(.bold))
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.7))
            Text(String(format: "%.3f", payslip.netToPay))
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cardInk, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func pdfPath(_ payslip: Payslip) -> String { "/payroll/payslips/\(payslip.id)/pdf" }

    private func pdfName(_ payslip: Payslip) -> String {
        "fiche-de-paie-\(payslip.employeeName)-\(payslip.periodLabel.replacingOccurrences(of: "/", with: "-")).pdf"
    }

    private func loadHistory() async {
        history = (try? await API.shared.get("/payroll/payslips")) ?? []
    }

    private func parse(_ file: UploadFile) async {
        uploading = true
        defer { uploading = false }
        do {
            let parsed: [PointageEmployee] = try await API.shared.upload("/payroll/parse-pointage", field: "file", files: [file])
            guard !parsed.isEmpty else { throw APIError(status: 0, message: tr("payroll.readFailed")) }
            employees = parsed
            selectedID = parsed.first?.id
            fileName = file.filename
            toast("\(tr("payroll.parsed")) \(parsed.count) \(tr("payroll.employeesWord"))")
        } catch {
            toast("\(tr("payroll.readFailed")) — \(error.localizedDescription)", error: true)
        }
    }

    private func show(_ payslip: Payslip) async {
        current = payslip
        currentPDF = nil
        do {
            let url = try await API.shared.download(pdfPath(payslip), filename: pdfName(payslip))
            if current?.id == payslip.id { currentPDF = url }
        } catch {
            toast("\(tr("payroll.downloadFailed")) — \(error.localizedDescription)", error: true)
        }
    }

    private func generate() async {
        guard let employee = selected else {
            toast(tr("payroll.uploadFirst"), error: true)
            return
        }
        guard rateValue > 0 else {
            toast(tr("payroll.enterRate"), error: true)
            return
        }
        busy = true
        defer { busy = false }
        do {
            let payslip: Payslip = try await API.shared.post("/payroll/payslips", body: NewPayslip(
                employeeName: employee.employeeName,
                matricule: employee.matricule,
                rows: employee.rows,
                hourlyRate: rateValue,
                advances: Fmt.parse(advances) ?? 0,
                pause: Fmt.parse(pause) ?? 0,
                m25: Fmt.parse(m25) ?? 0,
                m50: Fmt.parse(m50) ?? 0,
                m100: Fmt.parse(m100) ?? 0,
                companyName: companyName,
                companyAddress: companyAddress,
                companyContact: companyContact,
                currency: "TND"
            ))
            toast(tr("payroll.generated"))
            await loadHistory()
            await show(payslip)
        } catch {
            toast("\(tr("payroll.generateFailed")) — \(error.localizedDescription)", error: true)
        }
    }

    private func remove(_ payslip: Payslip) async {
        try? await API.shared.delete("/payroll/payslips/\(payslip.id)")
        if current?.id == payslip.id {
            current = nil
            currentPDF = nil
        }
        await loadHistory()
    }
}
