import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var auth: AuthStore
    @State private var confirmLogout = false

    var body: some View {
        Form {
            if let user = auth.user {
                Section(tr("settings.account")) {
                    HStack(spacing: 14) {
                        Text(initials(user.name))
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(Color.brand, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name).font(.headline)
                            Text(user.email).font(.subheadline).foregroundStyle(Color.muted)
                        }
                        Spacer()
                        StatusBadge(tr("roles.\(user.role)"), tone: user.isAdmin ? .brand : .neutral)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section(tr("settings.language")) {
                Picker(tr("settings.language"), selection: $settings.language) {
                    Text("English").tag("en")
                    Text("العربية").tag("ar")
                }
                .pickerStyle(.segmented)
            }

            Section(tr("settings.appearance")) {
                Picker(tr("settings.appearance"), selection: $settings.theme) {
                    Text(tr("settings.system")).tag("system")
                    Text(tr("settings.light")).tag("light")
                    Text(tr("settings.dark")).tag("dark")
                }
                .pickerStyle(.segmented)
            }

            ServerSettingsSection()

            Section {
                Button(tr("header.logout"), role: .destructive) { confirmLogout = true }
            }
        }
        .navigationTitle(tr("nav.settings"))
        .confirmationDialog(tr("header.logout"), isPresented: $confirmLogout, titleVisibility: .visible) {
            Button(tr("header.logout"), role: .destructive) { auth.logout() }
        }
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first?.uppercased() }.joined()
    }
}

/// Backend address, editable both from Settings and the login screen.
struct ServerSettingsSection: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var draft = ""
    @State private var testing = false

    var body: some View {
        Section {
            TextField(AppSettings.defaultServerURL, text: $draft)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit(save)
            Button {
                save()
                Task { await test() }
            } label: {
                HStack {
                    Text(tr("settings.testConnection"))
                    if testing { Spacer(); ProgressView() }
                }
            }
            .disabled(testing)
        } header: {
            Text(tr("settings.serverAddress"))
        } footer: {
            Text(tr("settings.serverHint"))
        }
        .onAppear { draft = settings.serverURL }
        .onDisappear(perform: save)
    }

    private func save() {
        let value = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { settings.serverURL = value }
    }

    private func test() async {
        testing = true
        defer { testing = false }
        do {
            // /openapi.json is public, so this works before signing in.
            let _: [String: AnyCodable] = try await API.shared.get("/openapi.json")
            toast(tr("settings.connectionOk"))
        } catch {
            toast("\(tr("settings.connectionFailed")) — \(error.localizedDescription)", error: true)
        }
    }
}

struct ServerSettingsForm: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form { ServerSettingsSection() }
            .navigationTitle(L10n.t("settings.server", lang: "en"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("common.done", lang: "en")) { dismiss() }
                }
            }
    }
}

/// Accepts any JSON value; used where only reachability matters.
struct AnyCodable: Codable {
    init(from decoder: Decoder) throws {}
    func encode(to encoder: Encoder) throws {}
}
