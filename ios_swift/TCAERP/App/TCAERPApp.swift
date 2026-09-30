import SwiftUI

@main
struct TCAERPApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var auth = AuthStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(auth)
                .preferredColorScheme(settings.colorScheme)
                .tint(.brand)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        ZStack {
            if auth.token == nil {
                // Login is always English, left-to-right (as on the web).
                LoginView()
                    .environment(\.layoutDirection, .leftToRight)
                    .transition(.opacity)
            } else {
                MainTabView()
                    // Rebuild the tree when the language flips so every
                    // tr(...) call re-reads the new strings.
                    .id(settings.language)
                    .environment(\.layoutDirection, settings.isRTL ? .rightToLeft : .leftToRight)
                    .environment(\.locale, Locale(identifier: settings.language))
                    .transition(.opacity)
            }
            ToastOverlay()
        }
        .animation(.easeInOut(duration: 0.25), value: auth.token == nil)
        .task(id: auth.token) { await auth.refresh() }
    }
}
