import SwiftUI

/// Cross-tab navigation state: selected tab, global sheets, and the
/// accounting country (so search results can jump to an invoice's ledger).
@MainActor
final class Router: ObservableObject {
    enum Tab: Hashable { case dashboard, clients, accounting, requests, more }

    enum Sheet: Identifiable {
        case search, notifications, chat(snapshot: UIImage?)

        var id: String {
            switch self {
            case .search: return "search"
            case .notifications: return "notifications"
            case .chat: return "chat"
            }
        }
    }

    @Published var tab: Tab = .dashboard
    @Published var sheet: Sheet?
    @Published var accountingCountry: Country = .tunisia
}

/// Replaces the web sidebar with a native tab bar. What's visible mirrors
/// AppShell.jsx: agents get Dashboard, Stats, Clients and Employee Requests;
/// admins get everything.
struct MainTabView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var router = Router()
    @StateObject private var chat = ChatStore()
    @StateObject private var alerts = AlertsStore()

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack { DashboardView() }
                .tabItem { Label(tr("nav.dashboard"), systemImage: "square.grid.2x2") }
                .tag(Router.Tab.dashboard)

            ClientsListView()
                .tabItem { Label(tr("nav.clients"), systemImage: "person.2") }
                .tag(Router.Tab.clients)

            if auth.isAdmin {
                NavigationStack { AccountingView() }
                    .tabItem { Label(tr("nav.accounting"), systemImage: "building.columns") }
                    .tag(Router.Tab.accounting)
            }

            NavigationStack { EmployeeRequestsView() }
                .tabItem { Label(tr("nav.requests"), systemImage: "tray.full") }
                .tag(Router.Tab.requests)

            NavigationStack { MoreView() }
                .tabItem { Label(tr("nav.more"), systemImage: "ellipsis.circle") }
                .tag(Router.Tab.more)
        }
        .environmentObject(router)
        .environmentObject(chat)
        .environmentObject(alerts)
        .sheet(item: $router.sheet) { sheet in
            Group {
                switch sheet {
                case .search:
                    SearchView()
                case .notifications:
                    NotificationsView()
                case .chat(let snapshot):
                    NavigationStack { ChatView(snapshot: snapshot, showsClose: true) }
                }
            }
            .environmentObject(router)
            .environmentObject(chat)
            .environmentObject(alerts)
            .environmentObject(auth)
        }
        .task(id: auth.isAdmin) { await alerts.poll(isAdmin: auth.isAdmin) }
    }
}

/// Search, notifications and assistant buttons shown on every tab's root
/// screen — what the web header bar held.
struct RootToolbar: ViewModifier {
    @EnvironmentObject private var router: Router
    @EnvironmentObject private var alerts: AlertsStore

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { router.sheet = .search } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(tr("header.search"))

                Button { router.sheet = .notifications } label: {
                    Image(systemName: alerts.count > 0 ? "bell.badge" : "bell")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(alerts.hasNegative ? Color.danger : Color.accentOrange, Color.brand)
                }
                .accessibilityLabel(tr("header.notifications"))

                Button {
                    // Snapshot before the sheet covers the screen, for the
                    // assistant's "live helper" mode.
                    router.sheet = .chat(snapshot: captureKeyWindow())
                } label: {
                    Image(systemName: "sparkles")
                }
                .accessibilityLabel(tr("nav.aiChatbot"))
            }
        }
    }
}

extension View {
    func rootToolbar() -> some View { modifier(RootToolbar()) }
}

struct MoreView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        List {
            Section {
                NavigationLink { StatsView() } label: {
                    Label(tr("nav.stats"), systemImage: "chart.bar.xaxis")
                }
                NavigationLink { ChatView(snapshot: nil, showsClose: false) } label: {
                    Label(tr("nav.aiChatbot"), systemImage: "sparkles")
                }
            }

            if auth.isAdmin {
                Section(tr("requests.myRequestsKicker")) {
                    NavigationLink { AgencyRequestsView() } label: {
                        Label(tr("nav.myRequests"), systemImage: "doc.text")
                    }
                    NavigationLink { PayrollView() } label: {
                        Label(tr("nav.payroll"), systemImage: "banknote")
                    }
                }
                Section(tr("users.kicker")) {
                    NavigationLink { UsersView() } label: {
                        Label(tr("nav.users"), systemImage: "person.badge.shield.checkmark")
                    }
                }
            }

            Section {
                NavigationLink { SettingsView() } label: {
                    Label(tr("nav.settings"), systemImage: "gearshape")
                }
            }
        }
        .navigationTitle(tr("nav.more"))
        .rootToolbar()
    }
}
