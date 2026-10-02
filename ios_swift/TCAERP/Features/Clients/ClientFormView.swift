import SwiftUI

/// Add or edit a client (AddClientPage.jsx / EditClientPage.jsx). In add
/// mode a passport photo can be run through the AI extractor to prefill
/// the passport fields.
struct ClientFormView: View {
    enum Mode {
        case add
        case edit(Client)
    }

    let mode: Mode
    var onSaved: (Client) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var passportImage: UIImage?
    @State private var photo: UIImage?
    @State private var otherFiles: [UploadFile] = []
    @State private var extracting = false
    /// Per passport field after reading: "verified", "likely" or "review".
    @State private var confidence: [String: String] = [:]
    @State private var saving = false
    @State private var showImporter = false

    private var isAdd: Bool { if case .add = mode { return true } else { return false } }
    private var existing: Client? { if case .edit(let c) = mode { return c } else { return nil } }

    var body: some View {
        Form {
            if isAdd {
                Section {
                    if let passportImage {
                        Image(uiImage: passportImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 220)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .frame(maxWidth: .infinity)
                    }
                    ImageSourceMenu(onImage: { passportImage = $0 }) {
                        Label(tr("clients.uploadPassport"), systemImage: "person.text.rectangle")
                    }
                    Button {
                        Task { await extract() }
                    } label: {
                        HStack {
                            Label(tr("clients.extractViaAi"), systemImage: "text.viewfinder")
                            if extracting { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(passportImage == nil || extracting)
                } header: {
                    Text(tr("clients.uploadPassport"))
                } footer: {
                    Text(tr("clients.savedWithFiles"))
                }
            }

            Section {
                HStack(spacing: 16) {
                    Group {
                        if let photo {
                            Image(uiImage: photo).resizable().scaledToFill()
                        } else {
                            AuthImage(path: existing?.displayPhoto)
                        }
                    }
                    .frame(width: 72, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    ImageSourceMenu(onImage: { photo = $0 }) {
                        Label(isAdd ? tr("clients.uploadPhoto") : tr("clients.replacePhoto"), systemImage: "camera")
                    }
                }
            } header: {
                Text(isAdd ? tr("clients.uploadPhoto") : tr("clients.replacePhoto"))
            } footer: {
                Text(isAdd ? tr("clients.manualUpload") : tr("clients.optional"))
            }

            Section(tr("clients.passportInfo")) {
                ForEach(ClientFields.passport, id: \.self) { key in
                    field(key)
                }
            }

            Section(tr("clients.contactBusiness")) {
                Picker(tr("clients.fields.category").capitalizedFirst, selection: binding("category")) {
                    ForEach(ClientCategory.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if values["category"] == ClientCategory.fair.rawValue {
                    LabeledField(label: tr("clients.fields.fair_email"), text: binding("fair_email"),
                                 keyboard: .emailAddress, autocapitalize: .never)
                }
                Picker(tr("clients.visaStatus"), selection: binding("visa_status")) {
                    Text(tr("clients.selectValue")).tag("")
                    ForEach(VisaStatus.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker(tr("clients.fields.visa_type").capitalizedFirst, selection: binding("visa_type")) {
                    Text(tr("clients.selectValue")).tag("")
                    ForEach(VisaType.allCases) { Text($0.label).tag($0.rawValue) }
                }
                if values["visa_type"] == VisaType.other.rawValue {
                    LabeledField(label: tr("clients.fields.visa_type_other"), text: binding("visa_type_other"))
                }
                Picker(tr("clients.fields.paiement_type").capitalizedFirst, selection: binding("paiement_type")) {
                    Text(tr("clients.selectValue")).tag("")
                    ForEach(PaymentMethod.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker(tr("clients.fields.payment_state").capitalizedFirst, selection: binding("payment_state")) {
                    Text(tr("clients.selectValue")).tag("")
                    ForEach(PaymentState.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker(tr("clients.fields.currency").capitalizedFirst, selection: binding("currency")) {
                    Text(tr("clients.selectValue")).tag("")
                    ForEach(Currency.allCases) { Text($0.label).tag($0.rawValue) }
                }
                ForEach(ClientFields.business, id: \.self) { key in
                    field(key)
                }
            }

            Section(tr("clients.travel")) {
                Toggle(tr("clients.fields.has_flight").capitalizedFirst, isOn: flag("has_flight"))
                if values["has_flight"] == "true" {
                    OptionalDateField(label: tr("clients.fields.flight_date"), text: binding("flight_date"))
                }
                LabeledField(label: tr("clients.fields.destination"), text: binding("destination"), autocapitalize: .words)
            }

            if values["category"] == ClientCategory.reservation.rawValue {
                Section(tr("clients.reservationDetails")) {
                    if values["has_flight"] == "true" {
                        LabeledField(label: tr("clients.fields.airline_name"), text: binding("airline_name"), autocapitalize: .words)
                    }
                    Toggle(tr("clients.fields.hotel_reservation").capitalizedFirst, isOn: flag("hotel_reservation"))
                    if values["hotel_reservation"] == "true" {
                        LabeledField(label: tr("clients.fields.hotel_name"), text: binding("hotel_name"), autocapitalize: .words)
                    }
                    LabeledField(label: tr("clients.fields.duration"), text: binding("duration"))
                    LabeledField(label: tr("clients.fields.reservation_amount"), text: binding("reservation_amount"), keyboard: .decimalPad)
                }
            }

            if isAdd {
                Section {
                    ForEach(Array(otherFiles.enumerated()), id: \.offset) { index, file in
                        HStack {
                            Image(systemName: "doc").foregroundStyle(Color.brand)
                            Text(file.filename).lineLimit(1)
                        }
                        .swipeActions {
                            Button(tr("common.remove"), role: .destructive) { otherFiles.remove(at: index) }
                        }
                    }
                    Button { showImporter = true } label: {
                        Label(tr("clients.uploadOtherDocs"), systemImage: "paperclip")
                    }
                } header: {
                    Text(tr("clients.otherFiles"))
                } footer: {
                    Text(tr("clients.otherDocsHint"))
                }
            }

            Section {
                PrimaryButton(title: isAdd ? tr("clients.saveToDatabase") : tr("clients.saveChanges"), loading: saving) {
                    Task { await save() }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(isAdd ? tr("clients.addClient") : tr("clients.editClient"))
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
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                otherFiles += urls.compactMap(UploadFile.from(url:))
            }
        }
        .onAppear {
            guard values.isEmpty else { return }
            if let existing {
                values = Dictionary(uniqueKeysWithValues: ClientFields.all.map { ($0, existing.value(for: $0)) })
            } else {
                values = Dictionary(uniqueKeysWithValues: ClientFields.all.map { ($0, "") })
                values["category"] = ClientCategory.normal.rawValue
                values["visa_status"] = VisaStatus.new.rawValue
                values["has_flight"] = "false"
                values["hotel_reservation"] = "false"
            }
        }
    }

    /// Editing a field means the user has checked it: its mark goes away.
    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { values[key] ?? "" }, set: { values[key] = $0; confidence[key] = nil })
    }

    /// Yes/no field, sent to the API as "true"/"false".
    private func flag(_ key: String) -> Binding<Bool> {
        Binding(get: { values[key] == "true" }, set: { values[key] = $0 ? "true" : "false" })
    }

    @ViewBuilder
    private func field(_ key: String) -> some View {
        let label = tr("clients.fields.\(key)")
        if key == "sex" {
            Picker(selection: binding(key)) {
                Text(tr("clients.selectValue")).tag("")
                Text("M").tag("M")
                Text("F").tag("F")
                Text("X").tag("X")
            } label: {
                HStack(spacing: 4) {
                    Text(label.capitalizedFirst)
                    ReadMark(status: confidence[key])
                }
            }
        } else if key.contains("date") {
            OptionalDateField(label: label, text: binding(key), status: confidence[key])
        } else {
            LabeledField(
                label: label,
                text: binding(key),
                keyboard: key == "prix_dossier" ? .decimalPad : key == "email" ? .emailAddress : key == "phone" ? .phonePad : .default,
                autocapitalize: ["email", "passport_number"].contains(key) ? .never : (key == "currency" ? .characters : .words),
                status: confidence[key]
            )
        }
    }

    private func extract() async {
        guard let passportImage, let file = UploadFile.jpeg(passportImage, name: "passport.jpg") else {
            toast(tr("clients.uploadFirst"), error: true)
            return
        }
        extracting = true
        defer { extracting = false }
        do {
            let result: ExtractResult = try await API.shared.upload("/extract", field: "file", files: [file])
            for (key, value) in result.fields { values[key] = value }
            // A field the reading left empty is also something to fill in.
            confidence = Dictionary(uniqueKeysWithValues: ClientFields.passport.map { key in
                (key, (result.fields[key] ?? "").isEmpty ? "review" : (result._meta?.status(for: key) ?? "likely"))
            })
            if result._meta?.engine == "ai" {
                toast(tr("clients.extractedAi"), error: true)
            } else {
                let seconds = String(format: "%.1f", Double(result._meta?.ms ?? 0) / 1000)
                toast(tr("clients.extractedOcr").replacingOccurrences(of: "{s}", with: seconds))
            }
        } catch {
            toast("\(tr("clients.extractFailed")) — \(error.localizedDescription)", error: true)
        }
    }

    private func save() async {
        guard !(values["given_name"] ?? "").isEmpty, !(values["surname"] ?? "").isEmpty,
              !(values["passport_number"] ?? "").isEmpty else {
            toast(tr("clients.requiredFields"), error: true)
            return
        }
        saving = true
        defer { saving = false }

        var body = values
        body["prix_dossier"] = body["prix_dossier"]?.replacingOccurrences(of: ",", with: ".")
        body["reservation_amount"] = body["reservation_amount"]?.replacingOccurrences(of: ",", with: ".")
        body["user_photo"] = photo?.dataURL() ?? ""

        do {
            let response: ClientSaveResponse
            if let existing {
                response = try await API.shared.put("/clients/\(existing.id)", body: body)
                toast(tr("clients.updated"))
            } else {
                response = try await API.shared.post("/clients", body: body)
                let uploads = [passportImage.flatMap { UploadFile.jpeg($0, name: "passport.jpg") }].compactMap { $0 } + otherFiles
                if !uploads.isEmpty {
                    let _: [ClientFile]? = try? await API.shared.upload("/clients/\(response.client.id)/files", field: "files", files: uploads)
                }
                toast(tr("clients.saved"))
            }
            onSaved(response.client)
            dismiss()
        } catch {
            toast("\(isAdd ? tr("clients.saveFailed") : tr("clients.updateFailed")) — \(error.localizedDescription)", error: true)
        }
    }
}
