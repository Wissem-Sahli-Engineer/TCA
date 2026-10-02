import SwiftUI

/// One client's file (src/features/clients/ClientDetailPage.jsx), plus
/// uploading extra documents from the phone.
struct ClientDetailView: View {
    let clientID: Int
    var onChange: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @StateObject private var previewer = FilePreviewer()
    @State private var client: Client?
    @State private var missing = false
    @State private var files: [ClientFile] = []
    @State private var showEdit = false
    @State private var confirmRemove = false
    @State private var fileToRemove: ClientFile?
    @State private var showImporter = false
    @State private var uploading = false

    var body: some View {
        Group {
            if let client {
                content(client)
            } else if missing {
                EmptyRow(text: tr("clients.notFound"), systemImage: "person.crop.circle.badge.xmark")
            } else {
                ProgressView(tr("clients.loadingFile"))
            }
        }
        .navigationTitle(client?.fullName ?? tr("clients.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .filePreview(previewer)
        .sheet(isPresented: $showEdit) {
            if let client {
                NavigationStack {
                    ClientFormView(mode: .edit(client)) { _ in
                        if let photo = client.userPhoto { API.shared.invalidateImage(photo) }
                        Task { await load() }
                        onChange()
                    }
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { await upload(urls.compactMap(UploadFile.from(url:))) }
            }
        }
        .confirmationDialog(tr("clients.removeConfirm"), isPresented: $confirmRemove, titleVisibility: .visible) {
            Button(tr("clients.removeClient"), role: .destructive) { Task { await removeClient() } }
        }
        .confirmationDialog(tr("clients.removeFile"), isPresented: Binding(
            get: { fileToRemove != nil }, set: { if !$0 { fileToRemove = nil } }
        ), titleVisibility: .visible) {
            Button(tr("common.remove"), role: .destructive) {
                if let file = fileToRemove { Task { await removeFile(file) } }
            }
        }
    }

    private func content(_ client: Client) -> some View {
        List {
            Section {
                VStack(spacing: 12) {
                    AuthImage(path: client.displayPhoto)
                        .frame(width: 130, height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text(client.fullName).font(.title2.weight(.bold)).multilineTextAlignment(.center)
                    Text(client.passportNumber).font(.subheadline.monospaced()).foregroundStyle(Color.muted)
                    ForEach(client.alertReasons, id: \.self) { reason in
                        Label(reason.text, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.danger)
                            .multilineTextAlignment(.center)
                    }
                    // One row when it fits, stacked when a long status wouldn't.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) { detailBadges(client) }
                        VStack(spacing: 6) { detailBadges(client) }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section(tr("clients.personalInfo")) {
                ForEach(fields(client), id: \.0) { label, value in
                    LabeledContent(label) {
                        Text(value.isEmpty ? "—" : value)
                            .foregroundStyle(value.isEmpty ? Color.muted : Color.ink)
                            .multilineTextAlignment(.trailing)
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                if files.isEmpty {
                    Text(tr("clients.noFiles")).foregroundStyle(Color.muted)
                }
                ForEach(files) { file in
                    Button {
                        Task { await previewer.open(file.url, filename: file.filename, failure: tr("invoicesTab.downloadFailed")) }
                    } label: {
                        HStack {
                            Image(systemName: icon(for: file)).foregroundStyle(Color.brand)
                            Text(file.filename).foregroundStyle(Color.ink).lineLimit(1)
                            Spacer()
                            if previewer.loadingPath == file.url { ProgressView() }
                        }
                    }
                    .swipeActions {
                        Button { fileToRemove = file } label: {
                            Label(tr("common.remove"), systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
                ImageSourceMenu(onImage: { image in
                    if let file = UploadFile.jpeg(image, name: "photo-\(Int(Date().timeIntervalSince1970)).jpg") {
                        Task { await upload([file]) }
                    }
                }) {
                    Label("\(tr("clients.addDocuments")) — \(tr("media.takePhoto"))", systemImage: "camera")
                }
                .disabled(uploading)
                Button { showImporter = true } label: {
                    HStack {
                        Label("\(tr("clients.addDocuments")) — \(tr("media.files"))", systemImage: "folder.badge.plus")
                        if uploading { Spacer(); ProgressView() }
                    }
                }
                .disabled(uploading)
            } header: {
                Text(tr("clients.documents"))
            }

            Section {
                Button(tr("clients.removeClient"), role: .destructive) { confirmRemove = true }
                    .frame(maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(tr("common.edit")) { showEdit = true }
            }
        }
    }

    @ViewBuilder
    private func detailBadges(_ client: Client) -> some View {
        StatusBadge(visa: client.visa)
        if let payment = client.payment { StatusBadge(payment: payment) }
        if client.clientCategory != .normal {
            StatusBadge(client.clientCategory.label, tone: .brand)
        }
    }

    private func fields(_ c: Client) -> [(String, String)] {
        let l = { (key: String) in tr("clients.labels.\(key)") }
        return [
            (l("fullName"), c.fullName),
            (l("dateOfBirth"), c.dateOfBirth ?? ""),
            (l("nationality"), c.nationality ?? ""),
            (l("passportNumber"), c.passportNumber),
            (l("expiry"), c.dateOfExpiry ?? ""),
            (l("placeOfBirth"), c.placeOfBirth ?? ""),
            (l("issuedBy"), c.issuedBy ?? ""),
            (l("phone"), c.phone ?? ""),
            (l("email"), c.email ?? ""),
            (l("entreprise"), c.entrepriseName ?? ""),
            (l("codeFiscal"), c.codeFiscal ?? ""),
            (l("category"), c.clientCategory.label),
        ]
        + (c.clientCategory == .fair ? [(l("fairEmail"), c.fairEmail ?? "")] : [])
        + [
            (l("visaStatus"), c.visa.label),
            (l("visaType"), c.visaTypeLabel),
            (l("prixDossier"), c.prixDossier.map(Fmt.num) ?? ""),
            (l("paiementType"), c.paiementType.map { PaymentMethod(rawValue: $0)?.label ?? $0 } ?? ""),
            (l("paymentState"), c.payment?.label ?? ""),
            (l("currency"), c.currency.map { Currency(rawValue: $0)?.label ?? $0 } ?? ""),
            (l("hasFlight"), c.hasFlight == true ? tr("common.yes") : tr("common.no")),
        ]
        + (c.hasFlight == true ? [(l("flightDate"), c.flightDate ?? "")] : [])
        + [(l("destination"), c.destination ?? "")]
        + (c.clientCategory == .reservation ? reservationFields(c) : [])
        + [(l("addedBy"), c.createdBy ?? "")]
    }

    private func reservationFields(_ c: Client) -> [(String, String)] {
        let l = { (key: String) in tr("clients.labels.\(key)") }
        return (c.hasFlight == true ? [(l("airlineName"), c.airlineName ?? "")] : [])
            + [(l("hotelReservation"), c.hotelReservation == true ? tr("common.yes") : tr("common.no"))]
            + (c.hotelReservation == true ? [(l("hotelName"), c.hotelName ?? "")] : [])
            + [
                (l("duration"), c.duration ?? ""),
                (l("reservationAmount"), c.reservationAmount.map(Fmt.num) ?? ""),
            ]
    }

    private func icon(for file: ClientFile) -> String {
        let type = file.contentType ?? ""
        if type.hasPrefix("image/") { return "photo" }
        if type.contains("pdf") { return "doc.richtext" }
        return "doc"
    }

    private func load() async {
        do {
            client = try await API.shared.get("/clients/\(clientID)")
            missing = false
        } catch {
            if client == nil { missing = true }
        }
        files = (try? await API.shared.get("/clients/\(clientID)/files")) ?? files
    }

    private func upload(_ uploads: [UploadFile]) async {
        guard !uploads.isEmpty else { return }
        uploading = true
        defer { uploading = false }
        do {
            let _: [ClientFile] = try await API.shared.upload("/clients/\(clientID)/files", field: "files", files: uploads)
            toast(tr("clients.uploaded"))
            await load()
        } catch {
            toast("\(tr("clients.uploadFailed")) — \(error.localizedDescription)", error: true)
        }
    }

    private func removeFile(_ file: ClientFile) async {
        try? await API.shared.delete("/clients/\(clientID)/files/\(file.id)")
        await load()
    }

    private func removeClient() async {
        do {
            try await API.shared.delete("/clients/\(clientID)")
            toast(tr("clients.removed"))
            onChange()
            dismiss()
        } catch {
            toast(tr("clients.removeFailed"), error: true)
        }
    }
}
