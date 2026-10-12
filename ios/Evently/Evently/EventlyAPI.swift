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

    private static let zoned = ISO8601DateFormatter()
    private static let zonedFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let local: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    /// A timestamp with a zone ("…Z", "…+05:00") is an exact moment; one without is wall-clock time at the venue.
    var date: Date? {
        Self.zoned.date(from: startsAt) ?? Self.zonedFractional.date(from: startsAt) ?? Self.local.date(from: String(startsAt.prefix(19)))
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
    var statusLabel: String {
        switch status {
        case "draft": "Черновик"
        case "published": "Опубликовано"
        case "hidden": "Скрыто"
        default: status
        }
    }
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
    var verifiedWallet: String? { walletVerifiedAt == nil ? nil : walletAddress }
    var managesEvents: Bool { role == "organizer" || role == "admin" }
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
    /// The Token-2022 ticket is not verified on-chain yet, so there is nothing to show at the door.
    var needsMint: Bool { blockchainStatus == "pending" || blockchainStatus == "failed" }
}

struct CheckInResult: Decodable {
    let eventTitle: String
    let explorerUrl: String?
    enum CodingKeys: String, CodingKey {
        case eventTitle = "event_title", explorerUrl = "explorer_url"
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
    var canCheckIn: Bool { !used && blockchainStatus == "confirmed" }
    var statusLabel: String {
        if used { return "Пришёл" }
        if status == "waitlisted" { return "Лист ожидания" }
        return blockchainStatus == "confirmed" ? "Билет выпущен" : "Билет не выпущен"
    }
}

struct AdminOverview: Codable {
    let events: Int
    let users: Int
    let registrations: Int
    let visits: Int
}

enum APIError: LocalizedError {
    case server(String, status: Int)
    case invalidResponse
    var errorDescription: String? {
        switch self {
        case .server(let message, _): message
        case .invalidResponse: "Не удалось прочитать ответ сервера"
        }
    }
    var status: Int? {
        if case .server(_, let status) = self { return status }
        return nil
    }

    static let alreadyExists = "Такая запись уже есть"

    /// The API answers in English; the app speaks Russian.
    static func localized(_ detail: String) -> String {
        switch detail {
        case "connect and verify Phantom wallet first", "connect and verify organizer Phantom wallet first":
            "Сначала подключи и подтверди кошелёк Phantom"
        case "sold out": "Мест больше нет"
        case "event has ended": "Событие уже завершилось"
        case "seats available": "Места ещё есть — можно получить билет"
        case "already exists": alreadyExists
        case "already used", "ticket already used": "Билет уже использован"
        case "ticket already confirmed": "Билет уже подтверждён"
        case "not your event": "Это не твоё событие"
        case "not found", "event not found", "registration not found": "Не найдено"
        case "blockchain ticket is not confirmed": "Билет ещё не подтверждён в Solana"
        case "wallet signature is invalid": "Подпись кошелька не подошла. Попробуй ещё раз"
        case "invalid Solana wallet": "Это не адрес кошелька Solana"
        case "invalid or expired token", "invalid refresh token": "Сессия истекла. Войди заново"
        case "organizer required": "Нужен аккаунт организатора"
        case "admin required": "Нужен аккаунт администратора"
        default: detail
        }
    }
}

enum KeychainStore {
    static let service = "com.miracleunvrs.evently.auth"
    static func load<Value: Decodable>(_ type: Value.Type, account: String) -> Value? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    static func save<Value: Encodable>(_ value: Value?, account: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        guard let value, let data = try? JSONEncoder().encode(value) else { return }
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
        tokens = KeychainStore.load(AuthTokens.self, account: "session")
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

    func call<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil,
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
        if http.statusCode == 401 && authenticated && retry, let refreshToken = tokens?.refreshToken {
            do {
                let fresh: AuthTokens = try await call("/auth/refresh", method: "POST",
                    body: ["refresh_token": refreshToken], retry: false)
                setTokens(fresh)
            } catch let error as APIError where error.status == 401 {
                // Only a rejected refresh token ends the session; a dropped connection must not sign the user out.
                signOut()
                throw error
            }
            return try await call(path, method: method, body: body, authenticated: true, retry: false)
        }
        guard (200...299).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw APIError.server(detail.map(APIError.localized) ?? "Ошибка сервера (\(http.statusCode))", status: http.statusCode)
        }
        if T.self == Empty.self { return Empty() as! T }
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.invalidResponse }
    }

    private func setTokens(_ fresh: AuthTokens) {
        tokens = fresh
        user = fresh.user
        KeychainStore.save(fresh, account: "session")
    }
    func signOut() {
        tokens = nil
        user = nil
        tickets = []
        waitlist = []
        favorites = []
        managed = []
        KeychainStore.save(nil as AuthTokens?, account: "session")
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
            managed = user?.managesEvents == true ? try await call("/me/events", authenticated: true) : []
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
        guard user != nil else { throw APIError.server("Сначала войди в аккаунт", status: 401) }
        if favorites.contains(event.id) {
            let _: Empty = try await call("/me/favorites/\(event.id)", method: "DELETE", authenticated: true)
            favorites.remove(event.id)
        } else {
            let _: Empty = try await call("/me/favorites", method: "POST", body: ["event_id": event.id], authenticated: true)
            favorites.insert(event.id)
        }
    }
    func joinWaitlist(_ event: Event) async throws {
        let entry: WaitlistEntry = try await conflict("Ты уже зарегистрирован на это событие") {
            try await self.call("/events/\(event.id)/waitlist", method: "POST", body: [:], authenticated: true)
        }
        waitlist.append(entry)
    }
    /// The API reports every uniqueness conflict the same way; say what it means for this request.
    private func conflict<Value>(_ message: String, _ work: () async throws -> Value) async throws -> Value {
        do { return try await work() } catch let error as APIError where error.status == 409 && error.errorDescription == APIError.alreadyExists {
            throw APIError.server(message, status: 409)
        }
    }
    func walletChallenge(address: String) async throws -> String {
        struct Challenge: Decodable { let message: String }
        let challenge: Challenge = try await call("/wallet/challenge", method: "POST", body: ["wallet_address": address], authenticated: true)
        return challenge.message
    }
    func verifyWallet(address: String, message: String, signature: Data) async throws {
        let _: Empty = try await conflict("Этот кошелёк уже привязан к другому аккаунту Evently") {
            try await self.call("/wallet/verify", method: "POST", body: [
                "wallet_address": address, "message": message, "signature": signature.base64EncodedString()], authenticated: true)
        }
        user = try await call("/auth/me", authenticated: true)
    }
    /// Reserves a seat and returns the ticket that still has to be minted on Solana.
    func register(eventId: Int) async throws -> Ticket {
        try await conflict("Ты уже зарегистрирован на это событие") {
            try await self.call("/events/\(eventId)/register", method: "POST", body: [:], authenticated: true)
        }
    }
    func confirmTicket(id: Int, signature: String, tokenAddress: String) async throws {
        let _: Ticket = try await call("/tickets/\(id)/blockchain", method: "POST", body: [
            "solana_signature": signature, "token_address": tokenAddress], authenticated: true)
    }
    func prepareCheckIn(code: String) async throws -> String {
        struct Prepared: Decodable { let memo: String }
        let prepared: Prepared = try await call("/check-in/prepare", method: "POST", body: ["code": code], authenticated: true)
        return prepared.memo
    }
    func checkIn(code: String, signature: String) async throws -> CheckInResult {
        try await call("/check-in", method: "POST", body: ["code": code, "check_in_signature": signature], authenticated: true)
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

struct Empty: Decodable {}
