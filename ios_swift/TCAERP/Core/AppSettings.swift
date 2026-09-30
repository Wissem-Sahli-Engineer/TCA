import SwiftUI

/// User-level preferences that persist across launches: backend address,
/// language and appearance.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    /// The Mac's Bonjour name rather than its IP, so it keeps working when
    /// the Mac's Wi-Fi address changes. Phone and Mac must share a network.
    static let defaultServerURL = "http://Wissems-MacBook-Air.local:8001"

    /// Earlier defaults, replaced on launch if a device still has them saved.
    private static let retiredDefaults = ["http://10.30.30.41:8001"]

    @Published var serverURL: String {
        didSet { UserDefaults.standard.set(serverURL, forKey: Keys.server) }
    }

    @Published var language: String {
        didSet {
            UserDefaults.standard.set(language, forKey: Keys.language)
            L10n.language = language
        }
    }

    /// "system" | "light" | "dark"
    @Published var theme: String {
        didSet { UserDefaults.standard.set(theme, forKey: Keys.theme) }
    }

    var isRTL: Bool { language == "ar" }

    var colorScheme: ColorScheme? {
        switch theme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private enum Keys {
        static let server = "serverURL"
        static let language = "language"
        static let theme = "theme"
    }

    private init() {
        let defaults = UserDefaults.standard
        let saved = defaults.string(forKey: Keys.server)
        if let saved, Self.retiredDefaults.contains(saved) {
            defaults.removeObject(forKey: Keys.server)
            serverURL = Self.defaultServerURL
        } else {
            serverURL = saved ?? Self.defaultServerURL
        }
        let lang = defaults.string(forKey: Keys.language) ?? "en"
        language = lang
        theme = defaults.string(forKey: Keys.theme) ?? "system"
        L10n.language = lang
    }
}
