import SwiftUI

/// Vacations / salary advances / loans (EmployeeRequestsPage.jsx). Agents
/// only ever see their own requests; the admin sees everyone's.
struct EmployeeRequestsView: View {
    enum Category: String, CaseIterable, Identifiable {
        case vacations, salaryAdvances = "salary-advances", loans
        var id: String { rawValue }
        var label: String {
            switch self {
            case .vacations: return tr("requests.vacations")
            case .salaryAdvances: return tr("requests.salaryAdvances")
            case .loans: return tr("requests.loans")
            }
        }
        var icon: String {
            switch self {
            case .vacations: return "beach.umbrella"
            case .salaryAdvances: return "banknote"
            case .loans: return "dollarsign.circle"
            }
        }
    }

    @EnvironmentObject private var auth: AuthStore
    @State private var category: Category = .vacations
    @State private var requests: [EmployeeRequest] = []
    @State private var detail = ""
    @State private var date = Fmt.today()
    @State private var busy = false
    @State private var toRemove: EmployeeRequest?

    private var rows: [EmployeeRequest] { requests.filter { $0.category == category.rawValue } }

    /// The admin can remove any request; everyone else their own.
    private func canRemove(_ request: EmployeeRequest) -> Bool {
        auth.isAdmin || (request.userEmail != nil && request.userEmail == auth.user?.email)
    }

    var body: some View {
        List {
            Section {
                IconTabPicker(items: Category.allCases.map { c in
                    .init(value: c, label: c.label, systemImage: c.icon,
                          badge: requests.filter { $0.category == c.rawValue && $0.status == "pending" }.count)
                }, selection: $category)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            Section(tr("requests.newRequest")) {
                LabeledField(label: tr("requests.detail"), text: $detail, placeholder: tr("requests.detailPlaceholder"))
                DateField(label: tr("requests.submissionDate"), text: $date)
                PrimaryButton(title: tr("requests.submit"), systemImage: "paperplane.fill", loading: busy) {
                    Task { await submit() }
                }
            }

            Section(category.label) {
                if rows.isEmpty {
                    EmptyRow(text: tr("requests.noRequests"), systemImage: category.icon)
                }
                ForEach(rows) { request in
                    let removable = canRemove(request)
                    RequestRow(title: request.employeeName, detail: request.detail, date: request.submittedDate, status: request.status,
                               onRemove: removable ? { toRemove = request } : nil)
                        .swipeActions {
                            if removable {
                                Button { toRemove = request } label: {
                                    Label(tr("requests.remove"), systemImage: "trash")
                                }
                                .tint(.red)
                            }
                        }
                        .contextMenu {
                            if removable {
                                Button(tr("requests.remove"), systemImage: "trash", role: .destructive) { toRemove = request }
                            }
                        }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(tr("requests.employeeRequestsTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .rootToolbar()
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(tr("requests.removeConfirm"), isPresented: Binding(
            get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }
        ), titleVisibility: .visible) {
            Button(tr("requests.remove"), role: .destructive) {
                if let request = toRemove {
                    Task {
                        try? await API.shared.delete("/employee-requests/\(request.id)")
                        await load()
                    }
                }
            }
        }
    }

    private func load() async {
        requests = (try? await API.shared.get("/employee-requests")) ?? []
    }

    private func submit() async {
        guard let text = detail.nilIfBlank else {
            toast(tr("requests.describeRequest"), error: true)
            return
        }
        busy = true
        defer { busy = false }
        do {
            let _: EmployeeRequest = try await API.shared.post("/employee-requests", body: NewEmployeeRequest(
                category: category.rawValue, employeeName: auth.user?.name ?? "Employee", detail: text, submittedDate: date
            ))
            detail = ""
            toast(tr("requests.submitted"))
            await load()
        } catch {
            toast("\(tr("requests.submitFailed")) — \(error.localizedDescription)", error: true)
        }
    }
}

/// The agency's own requests (MyRequestsPage.jsx) — admin only.
struct AgencyRequestsView: View {
    @State private var requests: [AgencyRequest] = []
    @State private var name = ""
    @State private var description = ""
    @State private var date = Fmt.today()
    @State private var busy = false
    @State private var toRemove: AgencyRequest?

    var body: some View {
        List {
            Section(tr("requests.newRequest")) {
                LabeledField(label: tr("requests.name"), text: $name)
                LabeledField(label: tr("requests.description"), text: $description)
                DateField(label: tr("requests.submissionDate"), text: $date)
                PrimaryButton(title: tr("requests.submitRequest"), systemImage: "paperplane.fill", loading: busy) {
                    Task { await submit() }
                }
            }

            Section(tr("requests.myRequestsTitle")) {
                if requests.isEmpty {
                    EmptyRow(text: tr("requests.noRequests"), systemImage: "doc.text")
                }
                ForEach(requests) { request in
                    RequestRow(title: request.name, detail: request.description, date: request.submittedDate, status: request.status,
                               onRemove: { toRemove = request })
                        .swipeActions {
                            Button { toRemove = request } label: {
                                Label(tr("requests.remove"), systemImage: "trash")
                            }
                            .tint(.red)
                        }
                        .contextMenu {
                            Button(tr("requests.remove"), systemImage: "trash", role: .destructive) { toRemove = request }
                        }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(tr("requests.myRequestsTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(tr("requests.removeConfirm"), isPresented: Binding(
            get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }
        ), titleVisibility: .visible) {
            Button(tr("requests.remove"), role: .destructive) {
                if let request = toRemove {
                    Task {
                        try? await API.shared.delete("/agency-requests/\(request.id)")
                        await load()
                    }
                }
            }
        }
    }

    private func load() async {
        requests = (try? await API.shared.get("/agency-requests")) ?? []
    }

    private func submit() async {
        guard let n = name.nilIfBlank, let d = description.nilIfBlank else {
            toast(tr("requests.nameDescRequired"), error: true)
            return
        }
        busy = true
        defer { busy = false }
        do {
            let _: AgencyRequest = try await API.shared.post("/agency-requests", body: NewAgencyRequest(name: n, description: d, submittedDate: date))
            name = ""
            description = ""
            toast(tr("requests.submitted"))
            await load()
        } catch {
            toast("\(tr("requests.submitFailed")) — \(error.localizedDescription)", error: true)
        }
    }
}

struct RequestRow: View {
    let title: String
    let detail: String
    let date: String
    let status: String
    /// Shows a delete button when set (also reachable by swiping or long-press).
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(Color.ink.opacity(0.8))
                Text(date).font(.caption).foregroundStyle(Color.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                StatusBadge(status: status)
                if let onRemove {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .foregroundStyle(Color.danger)
                            .frame(width: 32, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(tr("requests.remove"))
                }
            }
        }
        .padding(.vertical, 2)
    }
}
