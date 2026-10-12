import SwiftUI

@main
struct EventlyApp: App {
    @StateObject private var api: EventlyAPI
    @StateObject private var wallet: WalletCoordinator

    init() {
        let api = EventlyAPI()
        _api = StateObject(wrappedValue: api)
        _wallet = StateObject(wrappedValue: WalletCoordinator(api: api))
    }

    var body: some Scene {
        WindowGroup {
            EventlyHome().environmentObject(api).environmentObject(wallet).tint(Palette.ink)
                .task { await start() }
                // Phantom answers a request by opening evently://phantom/…
                .onOpenURL { wallet.handle($0) }
        }
    }

    private func start() async {
        #if targetEnvironment(simulator)
        // End-to-end runs sign in through the launch environment instead of typing into the form.
        let environment = ProcessInfo.processInfo.environment
        if let email = environment["EVENTLY_TEST_EMAIL"], let password = environment["EVENTLY_TEST_PASSWORD"] {
            try? await api.login(email: email, password: password)
        }
        #endif
        await api.refresh()
    }
}

enum Palette {
    static let ink = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.94, green: 0.94, blue: 0.97, alpha: 1)
            : UIColor(red: 0.12, green: 0.14, blue: 0.19, alpha: 1)
    })
    static let onInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    })
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1)
            : UIColor(red: 0.98, green: 0.97, blue: 0.94, alpha: 1)
    })
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.13, green: 0.14, blue: 0.18, alpha: 1)
            : .white
    })
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1, green: 0.50, blue: 0.36, alpha: 1)
            : UIColor(red: 1, green: 0.34, blue: 0.18, alpha: 1)
    })
}

struct EventlyHome: View {
    @EnvironmentObject private var wallet: WalletCoordinator
    @State private var auth = false
    var body: some View {
        TabView {
            NavigationStack { DiscoverView() }.tabItem { Label("Афиша", systemImage: "sparkles.rectangle.stack") }
            NavigationStack { FavoritesView() }.tabItem { Label("Избранное", systemImage: "heart") }
            NavigationStack { TicketsView() }.tabItem { Label("Билеты", systemImage: "ticket") }
            NavigationStack { ProfileView() }.tabItem { Label("Профиль", systemImage: "person.crop.circle") }
        }
        .environment(\.openAuth, { auth = true })
        .sheet(isPresented: $auth) { AuthView() }
        .sheet(isPresented: Binding(get: { wallet.activity != nil }, set: { if !$0 { wallet.cancel() } })) {
            if let activity = wallet.activity { WalletActivitySheet(activity: activity) }
        }
    }
}

private struct OpenAuthKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
    var openAuth: () -> Void {
        get { self[OpenAuthKey.self] }
        set { self[OpenAuthKey.self] = newValue }
    }
}
