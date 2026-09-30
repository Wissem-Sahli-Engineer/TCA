import SwiftUI

/// Account administration (src/features/admin/UsersPage.jsx): approve or
/// reject signups, change roles, remove accounts.
struct UsersView: View {
    @EnvironmentObject private var auth: AuthStore
    @State private var users: [User] = []
    @State private var busyID: Int?
    @State private var toRemove: User?

    private var pending: [User] { users.filter { $0.status == "pending" } }
    private var others: [User] { users.filter { $0.status != "pending" } }

    var body: some View {
        List {
            if !pending.isEmpty {
                Section(tr("users.pendingRequests")) {
                    ForEach(pending) { user in
                        VStack(alignment: .leading, spacing: 10) {
                            UserInfo(user: user)
                            HStack {
                                Button {
                                    Task { await act(user, "approve") }
                                } label: {
                                    Label(tr("users.approve"), systemImage: "checkmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.success)

                                Button(role: .destructive) {
                                    Task { await act(user, "reject") }
                                } label: {
                                    Label(tr("users.reject"), systemImage: "xmark")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                            .disabled(busyID == user.id)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Section(tr("users.allAccounts")) {
                if others.isEmpty {
                    EmptyRow(text: tr("users.noAccounts"), systemImage: "person.3")
                }
                ForEach(others) { user in
                    let isMe = user.id == auth.user?.id
                    HStack {
                        UserInfo(user: user)
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            if isMe {
                                Text(tr("users.you")).font(.caption).foregroundStyle(Color.muted)
                            } else if user.status == "active" {
                                Menu {
                                    Picker(tr("users.roleCol"), selection: Binding(
                                        get: { user.role },
                                        set: { role in Task { await changeRole(user, role) } }
                                    )) {
                                        Text(tr("roles.Agent")).tag("Agent")
                                        Text(tr("roles.Admin")).tag("Admin")
                                    }
                                } label: {
                                    HStack(spacing: 3) {
                                        Text(tr("roles.\(user.role)"))
                                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                                    }
                                    .font(.subheadline.weight(.medium))
                                }
                                .disabled(busyID == user.id)
                            } else {
                                Text(tr("roles.\(user.role)")).font(.subheadline).foregroundStyle(Color.muted)
                            }
                            StatusBadge(status: user.status)
                        }
                    }
                    .swipeActions {
                        if !isMe {
                            Button(tr("users.remove"), role: .destructive) { toRemove = user }
                        }
                    }
                }
            }
        }
        .navigationTitle(tr("users.title"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .confirmationDialog(tr("users.removeConfirm"), isPresented: Binding(
            get: { toRemove != nil }, set: { if !$0 { toRemove = nil } }
        ), titleVisibility: .visible) {
            Button(tr("users.remove"), role: .destructive) {
                if let user = toRemove { Task { await remove(user) } }
            }
        }
    }

    private func load() async {
        users = (try? await API.shared.get("/auth/users")) ?? []
    }

    private func act(_ user: User, _ action: String) async {
        busyID = user.id
        defer { busyID = nil }
        do {
            try await API.shared.postVoid("/auth/users/\(user.id)/\(action)")
            toast(action == "approve" ? tr("users.approved") : tr("users.rejectedMsg"))
            await load()
        } catch {
            toast("\(tr("users.updateFailed")) — \(error.localizedDescription)", error: true)
        }
    }

    private func changeRole(_ user: User, _ role: String) async {
        guard role != user.role else { return }
        busyID = user.id
        defer { busyID = nil }
        do {
            try await API.shared.postVoid("/auth/users/\(user.id)/role", body: ["role": role])
            toast("\(tr("users.roleChanged")) \(tr("roles.\(role)"))")
            await load()
        } catch {
            toast("\(tr("users.roleChangeFailed")) — \(error.localizedDescription)", error: true)
        }
    }

    private func remove(_ user: User) async {
        busyID = user.id
        defer { busyID = nil }
        do {
            try await API.shared.delete("/auth/users/\(user.id)")
            toast(tr("users.removed"))
            await load()
        } catch {
            toast("\(tr("users.removeFailed")) — \(error.localizedDescription)", error: true)
        }
    }
}

private struct UserInfo: View {
    let user: User

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(user.name).font(.subheadline.weight(.semibold))
            Text(user.email).font(.caption).foregroundStyle(Color.muted)
        }
    }
}
