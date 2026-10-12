import Foundation
import Security

struct Event: Codable, Identifiable, Hashable {
    let id: Int
    let organizerId: Int
    let title: String
    let description: String
    let city: String
    let place: String
    let startsAt: String
    let capacity: Int
    let price: Int
    let status: String
    let coverUrl: String
    let category: String?
    let occupied: Int
    let visits: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, description, city, place, capacity, price, status, category, occupied, visits
        case organizerId = "organizer_id", startsAt = "starts_at", coverUrl = "cover_url"
    }

    var date: Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: String(startsAt.prefix(19)))
    }
    var dateLabel: String {
        guard let date else { return startsAt }
        return date.formatted(.dateTime.day().month(.wide).hour().minute().locale(Locale(identifier: "ru_KZ")))
    }
    var coverName: String {
        if coverUrl.contains("02-after-dark") { return "Cover2" }
        if coverUrl.contains("03-creative-play") { return "Cover3" }
        return "Cover1"
    }
    var available: Int { max(0, capacity - occupied) }
    var ended: Bool { date.map { $0 < Date() } ?? false }
}

struct Account: Codable {
    let id: Int
    let name: String
    let email: String
    let role: String
    let walletAddress: String?
    let walletVerifiedAt: String?
    enum CodingKeys: String, CodingKey {
        case id, name, email, role
        case walletAddress = "wallet_address", walletVerifiedAt = "wallet_verified_at"
    }
}

struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let user: Account
    enum CodingKeys: String, CodingKey {
        case user
        case accessToken = "access_token", refreshToken = "refresh_token"
    }
}

struct Ticket: Codable, Identifiable {
    let id: Int
    let code: String
    let status: String
    let eventId: Int
    let eventTitle: String
    let event: Event
    let registrationId: Int
    let walletAddress: String?
    let solanaSignature: String?
    let tokenAddress: String?
    let blockchainStatus: String
    let explorerUrl: String?
    let checkedInAt: String?
    enum CodingKeys: String, CodingKey {
        case id, code, status, event
        case eventId = "event_id", eventTitle = "event_title", registrationId = "registration_id"
        case walletAddress = "wallet_address", solanaSignature = "solana_signature"
        case tokenAddress = "token_address", blockchainStatus = "blockchain_status"
        case explorerUrl = "explorer_url", checkedInAt = "checked_in_at"
    }
}

struct WaitlistEntry: Codable, Identifiable {
    let registrationId: Int
    let eventId: Int
    let eventTitle: String
    let status: String
    let position: Int
    var id: Int { registrationId }
    enum CodingKeys: String, CodingKey {
        case status, position
        case registrationId = "registration_id", eventId = "event_id", eventTitle = "event_title"
    }
}

struct EventStats: Codable {
    let registrations: Int
    let visits: Int
    let capacity: Int
}

struct Guest: Codable, Identifiable {
    let name: String
    let email: String
    let status: String
    let code: String?
    let used: Bool
    let blockchainStatus: String?
    var id: String { email }
    enum CodingKeys: String, CodingKey {
        case name, email, status, code, used
        case blockchainStatus = "blockchain_status"
    }
}

struct AdminOverview: Codable {
    let events: Int
    let users: Int
    let registrations: Int
    let visits: Int
}

enum APIError: LocalizedError {
    case server(String)
    case invalidResponse
    var errorDescription: String? {
        switch self {
        case .server(let message): message
        case .invalidResponse: "Не удалось прочитать ответ сервера"
        }
    }
}

private enum TokenVault {
    static let service = "com.miracleunvrs.evently.auth"
    static func load() -> AuthTokens? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: "session",
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }
    static func save(_ tokens: AuthTokens?) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: "session"]
        SecItemDelete(query as CFDictionary)
        guard let tokens, let data = try? JSONEncoder().encode(tokens) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

@MainActor
final class EventlyAPI: ObservableObject {
    @Published var events: [Event] = []
    @Published var tickets: [Ticket] = []
    @Published var waitlist: [WaitlistEntry] = []
    @Published var favorites: Set<Int> = []
    @Published var managed: [Event] = []
    @Published var user: Account?
    @Published var loading = false
    @Published var error: String?
    @Published var apiAddress: String
    private var tokens: AuthTokens?

    init() {
        let configured = Bundle.main.object(forInfoDictionaryKey: "EventlyAPIURL") as? String
        apiAddress = UserDefaults.standard.string(forKey: "evently.api") ?? configured ??
            "https://evently-api-production-1056.up.railway.app"
        tokens = TokenVault.load()
        user = tokens?.user
    }

    func updateAddress(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned), url.host != nil, url.user == nil,
              url.scheme == "https" || (url.scheme == "http" && Self.isLocal(url.host!)) else { return false }
        apiAddress = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        UserDefaults.standard.set(apiAddress, forKey: "evently.api")
        return true
    }

    private static func isLocal(_ host: String) -> Bool {
        if host == "localhost" || host.hasSuffix(".local") { return true }
        let pieces = host.split(separator: ".").compactMap { Int($0) }
        guard pieces.count == 4, pieces.allSatisfy({ (0...255).contains($0) }) else { return false }
        return pieces[0] == 10 || pieces[0] == 127 ||
            (pieces[0] == 192 && pieces[1] == 168) ||
            (pieces[0] == 172 && (16...31).contains(pieces[1]))
    }

    private func call<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                                    authenticated: Bool = false, retry: Bool = true) async throws -> T {
        guard let url = URL(string: apiAddress + path) else { throw APIError.invalidResponse }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated, let token = tokens?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 && authenticated && retry && tokens != nil {
            do {
                let fresh: AuthTokens = try await call("/auth/refresh", method: "POST",
                    body: ["refresh_token": tokens!.refreshToken], retry: false)
                setTokens(fresh)
                return try await call(path, method: method, body: body, authenticated: true, retry: false)
            } catch {
                signOut()
                throw error
            }
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw APIError.server(detail ?? "Ошибка сервера (\(http.statusCode))")
        }
        if T.self == Empty.self { return Empty() as! T }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.invalidResponse }
    }

    private func setTokens(_ fresh: AuthTokens) {
        tokens = fresh
        user = fresh.user
        TokenVault.save(fresh)
    }
    func signOut() {
        tokens = nil
        user = nil
        tickets = []
        waitlist = []
        favorites = []
        managed = []
        TokenVault.save(nil)
    }
    func refresh() async {
        loading = true
        defer { loading = false }
        do {
            events = try await call("/events")
            error = nil
            if tokens != nil { await refreshPrivate() }
        } catch { self.error = error.localizedDescription }
    }
    func refreshPrivate() async {
        guard tokens != nil else { return }
        do {
            user = try await call("/auth/me", authenticated: true)
            tickets = try await call("/me/tickets", authenticated: true)
            waitlist = try await call("/me/waitlist", authenticated: true)
            let favoriteIds: [Int] = try await call("/me/favorites", authenticated: true)
            favorites = Set(favoriteIds)
            if user?.role == "organizer" || user?.role == "admin" {
                managed = try await call("/me/events", authenticated: true)
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
    func login(email: String, password: String) async throws {
        let fresh: AuthTokens = try await call("/auth/login", method: "POST", body: ["email": email, "password": password])
        setTokens(fresh)
        await refreshPrivate()
    }
    /// Returns false when the user closes the Google sheet without choosing an account.
    func loginWithGoogle() async throws -> Bool {
        guard let idToken = try await GoogleSignIn.shared.idToken() else { return false }
        let fresh: AuthTokens = try await call("/auth/google", method: "POST", body: ["id_token": idToken])
        setTokens(fresh)
        await refreshPrivate()
        return true
    }
    func register(name: String, email: String, password: String) async throws {
        let fresh: AuthTokens = try await call("/auth/register", method: "POST", body: [
            "name": name, "email": email, "password": password, "password_confirmation": password])
        setTokens(fresh)
        await refreshPrivate()
    }
    func toggleFavorite(_ event: Event) async throws {
        guard user != nil else { throw APIError.server("Сначала войдите в аккаунт") }
        if favorites.contains(event.id) {
            let _: Empty = try await call("/me/favorites/\(event.id)", method: "DELETE", authenticated: true)
            favorites.remove(event.id)
        } else {
            let _: Empty = try await call("/me/favorites", method: "POST", body: ["event_id": event.id], authenticated: true)
            favorites.insert(event.id)
        }
    }
    func joinWaitlist(_ event: Event) async throws {
        let entry: WaitlistEntry = try await call("/events/\(event.id)/waitlist", method: "POST", body: [:], authenticated: true)
        waitlist.append(entry)
    }
    func cancel(_ ticket: Ticket) async throws {
        let _: Empty = try await call("/registrations/\(ticket.registrationId)", method: "DELETE", authenticated: true)
        await refresh()
    }
    func stats(_ event: Event) async throws -> EventStats {
        try await call("/events/\(event.id)/stats", authenticated: true)
    }
    func guests(_ event: Event) async throws -> [Guest] {
        try await call("/events/\(event.id)/guests", authenticated: true)
    }
    func adminOverview() async throws -> AdminOverview {
        try await call("/admin/overview", authenticated: true)
    }
    func createEvent(title: String, description: String, city: String, place: String,
                     startsAt: Date, capacity: Int) async throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let _: Event = try await call("/events", method: "POST", body: [
            "title": title, "description": description, "city": city, "place": place,
            "starts_at": formatter.string(from: startsAt), "capacity": capacity,
            "price": 0, "status": "draft", "cover_url": "/covers/01-future-work.jpg"], authenticated: true)
        managed = try await call("/me/events", authenticated: true)
    }
}

private struct Empty: Decodable {}
