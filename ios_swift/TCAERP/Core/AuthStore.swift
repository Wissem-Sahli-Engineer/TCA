import Foundation
import Security

/// Session state. With "Remember me" the token goes to the Keychain and
/// survives relaunches; otherwise it lives only in memory for this run —
/// the same split as the web's localStorage vs sessionStorage.
@MainActor
final class AuthStore: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var token: String?

    var isAdmin: Bool { user?.isAdmin ?? false }

    private let userKey = "auth.user"

    init() {
        if let token = Keychain.read(), let data = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(User.self, from: data) {
            self.token = token
            self.user = user
        }
        API.shared.token = token
        API.shared.onUnauthorized = { [weak self] in self?.logout() }
    }

    func login(email: String, password: String, remember: Bool) async throws {
        struct Body: Encodable { let email: String; let password: String; let remember: Bool }
        let response: LoginResponse = try await API.shared.post(
            "/auth/login", body: Body(email: email, password: password, remember: remember)
        )
        Keychain.delete()
        UserDefaults.standard.removeObject(forKey: userKey)
        if remember {
            Keychain.save(response.token)
            if let data = try? JSONEncoder().encode(response.user) {
                UserDefaults.standard.set(data, forKey: userKey)
            }
        }
        API.shared.token = response.token
        token = response.token
        user = response.user
    }

    /// Signup doesn't sign in — the account stays "pending" until an admin
    /// approves it.
    func signup(name: String, email: String, password: String) async throws {
        struct Body: Encodable { let name: String; let email: String; let password: String }
        let _: MessageResponse = try await API.shared.post(
            "/auth/signup", body: Body(name: name, email: email, password: password)
        )
    }

    /// Re-validates a remembered session and picks up role changes.
    func refresh() async {
        guard token != nil else { return }
        if let me: User = try? await API.shared.get("/auth/me") {
            user = me
            if Keychain.read() != nil, let data = try? JSONEncoder().encode(me) {
                UserDefaults.standard.set(data, forKey: userKey)
            }
        }
    }

    func logout() {
        Keychain.delete()
        UserDefaults.standard.removeObject(forKey: userKey)
        API.shared.token = nil
        token = nil
        user = nil
    }
}

private enum Keychain {
    private static let service = "com.tca.erp.native"
    private static let account = "session-token"

    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ token: String) {
        var item = query
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func read() -> String? {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
