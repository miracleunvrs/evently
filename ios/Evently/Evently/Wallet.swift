import Combine
import CryptoKit
import SwiftUI
import UIKit

/// What the wallet sheet shows while a Phantom request is on its way.
struct WalletActivity: Equatable {
    enum Phase: Equatable {
        /// The request is open in Phantom and the answer has not come back yet.
        case waiting
        case progress(String)
        /// Connected; the account still needs a signature proving the wallet is the user's.
        case confirmWallet(String)
        case success(String)
        case failure(String)
        /// Phantom could not serve a Devnet connection; the user can carry on with a plain one.
        case devnetBlocked
    }
    var title: String
    var phase: Phase
}

enum WalletError: LocalizedError {
    case noFunds
    case phantomMissing
    var errorDescription: String? {
        switch self {
        case .noFunds:
            "На кошельке не хватает тестовых SOL. Нужно около 0.005 SOL в сети Devnet — их бесплатно выдаёт faucet.solana.com."
        case .phantomMissing:
            "Не получилось открыть Phantom. Установи приложение Phantom и включи в нём Testnet Mode (сеть Solana Devnet)."
        }
    }
}

/// Runs every Phantom round trip: connect, prove wallet ownership, mint a ticket, check a ticket in.
///
/// A request leaves the app and the answer arrives later as an `evently://phantom/...` link, possibly after iOS
/// has restarted the app. So the step in flight is stored, and `handle(_:)` finishes it from the stored state.
@MainActor
final class WalletCoordinator: ObservableObject {
    @Published var activity: WalletActivity?
    @Published private(set) var session: PhantomSession?
    /// What the user was doing when the wallet turned out not to be ready, offered again once it is.
    @Published private(set) var resume: (label: String, action: () -> Void)?

    private enum Operation: Codable {
        case connect(secretKey: Data, devnet: Bool)
        case verify(address: String, message: String)
        case mint(ticketId: Int, tokenAddress: String)
        case checkIn(code: String)

        var method: PhantomLink.Method {
            switch self {
            case .connect: .connect
            case .verify: .signMessage
            case .mint, .checkIn: .signTransaction
            }
        }
        var title: String {
            switch self {
            case .connect: "Подключение Phantom"
            case .verify: "Подтверждение кошелька"
            case .mint: "Выпуск билета"
            case .checkIn: "Проверка билета"
            }
        }
    }
    private struct Submitted: Codable {
        let signature: String
        let tokenAddress: String
    }
    private struct Stored: Codable {
        var session: PhantomSession?
        var operation: Operation?
        /// Mint transactions sent to the network but not confirmed by the API yet, by ticket id.
        var submitted: [Int: Submitted] = [:]
        /// Phantom failed on a Devnet connection, so connect without asking for a cluster.
        var skipDevnet: Bool?
    }

    private static let account = "wallet"
    private let api: EventlyAPI
    private let rpc = SolanaRPC(endpoint: WalletCoordinator.rpcEndpoint)
    private var stored: Stored {
        didSet {
            KeychainStore.save(stored, account: Self.account)
            session = stored.session
        }
    }
    private var lastRequest: URL?
    /// The ticket or check-in request in flight, to offer again after reconnecting.
    private var attempt: (label: String, action: () -> Void)?
    private var accountChange: AnyCancellable?

    init(api: EventlyAPI) {
        self.api = api
        stored = KeychainStore.load(Stored.self, account: Self.account) ?? Stored()
        session = stored.session
        // The wallet session belongs to the signed-in account.
        accountChange = api.$user.map { $0?.id }.removeDuplicates().dropFirst().sink { [weak self] _ in self?.reset() }
    }

    /// The Phantom session signs for the wallet this account has verified.
    func isReady(for user: Account?) -> Bool {
        session != nil && session?.walletAddress == user?.verifiedWallet
    }

    // MARK: Requests

    func connect() {
        let secretKey = PhantomLink.newSecretKey()
        let devnet = stored.skipDevnet != true
        stored.operation = .connect(secretKey: secretKey, devnet: devnet)
        activity = WalletActivity(title: "Подключение Phantom", phase: .waiting)
        do { open(try PhantomLink.connect(base: base, secretKey: secretKey, devnet: devnet)) } catch { fail(error) }
    }

    func confirmWallet() {
        guard let session else { return connect() }
        run("Подтверждение кошелька", "Готовим сообщение для подписи…") {
            let message = try await self.api.walletChallenge(address: session.walletAddress)
            self.stored.operation = .verify(address: session.walletAddress, message: message)
            // Same payload as Phantom's demo app. The optional "display" field stays out: utf8 is the default,
            // and requests that carry it have been reported to fail with Phantom's internal error on iOS.
            try self.request(.signMessage, ["message": Base58.encode(Data(message.utf8))], session)
        }
    }

    /// Reserves a seat (or picks up a ticket that is still waiting for its mint) and asks Phantom to mint the ticket.
    func issueTicket(eventId: Int) {
        attempt = ("Получить билет", { self.issueTicket(eventId: eventId) })
        guard let session = readySession(resume: "Получить билет", { self.issueTicket(eventId: eventId) }) else { return }
        run("Выпуск билета", "Бронируем место…") {
            let ticket = try await self.api.register(eventId: eventId)
            await self.api.refresh()
            if self.stored.submitted[ticket.id] != nil { return try await self.finishMint(ticketId: ticket.id) }
            guard let owner = SolanaKey(base58: session.walletAddress) else { throw PhantomError.invalidResponse }
            self.progress("Готовим билет в Solana…")
            async let blockhash = self.rpc.latestBlockhash()
            async let rent = self.rpc.minimumBalance(space: TicketTransaction.mintLength)
            async let balance = self.rpc.balance(of: session.walletAddress)
            // Rent for the mint account and for the token account, plus fees.
            guard try await balance >= 2 * (try await rent) + 100_000 else { throw WalletError.noFunds }
            let mintKey = Curve25519.Signing.PrivateKey()
            guard let mint = SolanaKey(bytes: mintKey.publicKey.rawRepresentation),
                  let transaction = TicketTransaction.mint(owner: owner, mint: mint, eventId: ticket.eventId,
                                                           registrationId: ticket.registrationId, rentLamports: try await rent,
                                                           recentBlockhash: try await blockhash) else { throw PhantomError.invalidResponse }
            let wire = transaction.serialized(signatures: [mint: try mintKey.signature(for: transaction.message)])
            self.stored.operation = .mint(ticketId: ticket.id, tokenAddress: mint.base58)
            try self.request(.signTransaction, ["transaction": Base58.encode(wire)], session)
        }
    }

    func checkIn(code: String) {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !code.isEmpty else { return }
        attempt = ("Проверить билет", { self.checkIn(code: code) })
        guard let session = readySession(resume: "Проверить билет", { self.checkIn(code: code) }) else { return }
        run("Проверка билета", "Ищем билет…") {
            let memo = try await self.api.prepareCheckIn(code: code)
            guard let organizer = SolanaKey(base58: session.walletAddress) else { throw PhantomError.invalidResponse }
            let transaction = TicketTransaction.checkIn(organizer: organizer, memo: memo, recentBlockhash: try await self.rpc.latestBlockhash())
            self.stored.operation = .checkIn(code: code)
            try self.request(.signTransaction, ["transaction": Base58.encode(transaction.serialized())], session)
        }
    }

    // MARK: Answers

    /// Handles a redirect from Phantom. Returns false when the link is not an answer to the request in flight.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let method = PhantomLink.method(of: url), let operation = stored.operation, operation.method == method else { return false }
        stored.operation = nil
        lastRequest = nil
        activity = WalletActivity(title: activity?.title ?? operation.title, phase: .progress("Получаем ответ Phantom…"))
        Task {
            do {
                try await finish(operation, url)
            } catch PhantomError.cancelled {
                if case .mint = operation {
                    fail("Подпись отменена. Место за тобой — выпустить билет можно во вкладке «Билеты».")
                } else {
                    activity = nil
                }
            } catch PhantomError.unauthorized {
                stored.session = nil
                fail(PhantomError.unauthorized)
            } catch PhantomError.internalError where usedDevnet(operation) {
                // Phantom answers a Devnet connection with its internal error when Testnet Mode is off.
                if case .verify = operation {} else if resume == nil { resume = attempt }
                activity?.phase = .devnetBlocked
            } catch {
                fail(error)
            }
        }
        return true
    }

    private func finish(_ operation: Operation, _ url: URL) async throws {
        switch operation {
        case .connect(let secretKey, let devnet):
            let connected = try PhantomLink.session(from: url, secretKey: secretKey, devnet: devnet)
            stored.session = connected
            if connected.walletAddress == api.user?.verifiedWallet {
                succeed("Кошелёк подключён")
            } else {
                activity?.phase = .confirmWallet(connected.walletAddress)
            }
        case .verify(let address, let message):
            guard let session, let signature = try PhantomLink.response(from: url, session: session)["signature"].flatMap(Base58.decode) else {
                throw PhantomError.invalidResponse
            }
            progress("Проверяем подпись…")
            try await api.verifyWallet(address: address, message: message, signature: signature)
            succeed("Кошелёк подтверждён")
        case .mint(let ticketId, let tokenAddress):
            let signature = try await submit(url)
            stored.submitted[ticketId] = Submitted(signature: signature, tokenAddress: tokenAddress)
            try await finishMint(ticketId: ticketId)
        case .checkIn(let code):
            let signature = try await submit(url)
            progress("Ждём подтверждения сети Solana…")
            try await rpc.waitForConfirmation(signature)
            progress("Отмечаем проход…")
            let result = try await retrying(status: 503) { try await self.api.checkIn(code: code, signature: signature) }
            await api.refresh()
            succeed("Проход разрешён · \(result.eventTitle)")
        }
    }

    /// Phantom only signs; the app sends the transaction to Devnet itself, whatever network Phantom is on.
    private func submit(_ url: URL) async throws -> String {
        guard let session, let signed = try PhantomLink.response(from: url, session: session)["transaction"].flatMap(Base58.decode) else {
            throw PhantomError.invalidResponse
        }
        progress("Отправляем в сеть Solana…")
        return try await rpc.send(signed)
    }

    private func usedDevnet(_ operation: Operation) -> Bool {
        if case .connect(_, let devnet) = operation { return devnet }
        return session?.usesDevnet ?? true
    }

    /// Waits for the mint to confirm and lets the API verify it. A submitted mint is kept until it has a verdict,
    /// so a retry after a dropped connection confirms the same token instead of minting a second one.
    private func finishMint(ticketId: Int) async throws {
        guard let sent = stored.submitted[ticketId] else { return }
        progress("Ждём подтверждения сети Solana…")
        do {
            try await rpc.waitForConfirmation(sent.signature)
        } catch let error as SolanaRPCError {
            stored.submitted[ticketId] = nil
            throw error
        }
        progress("Проверяем билет…")
        do {
            try await retrying(status: 422) {
                try await self.api.confirmTicket(id: ticketId, signature: sent.signature, tokenAddress: sent.tokenAddress)
            }
        } catch let error as APIError where error.status == 422 || error.status == 409 {
            stored.submitted[ticketId] = nil
            await api.refresh()
            throw error
        }
        stored.submitted[ticketId] = nil
        await api.refresh()
        succeed("Билет выпущен. QR-код ждёт во вкладке «Билеты».")
    }

    /// The API reads the chain through its own RPC node, which can lag a moment behind the one that confirmed to us.
    private func retrying<Value>(status: Int, attempts: Int = 5, _ work: () async throws -> Value) async throws -> Value {
        for _ in 1..<attempts {
            do { return try await work() } catch let error as APIError where error.status == status {
                try await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
        return try await work()
    }

    // MARK: Sheet actions

    func reopen() {
        if let lastRequest { open(lastRequest) }
    }

    func cancel() {
        stored.operation = nil
        lastRequest = nil
        resume = nil
        attempt = nil
        activity = nil
    }

    /// Reconnects without the Devnet cluster and carries on with what the user was doing.
    func continueWithoutDevnet() {
        stored.skipDevnet = true
        stored.session = nil
        connect()
    }

    func continueAfterWallet() {
        let action = resume?.action
        resume = nil
        action?()
    }

    /// Connects Phantom, or finishes proving ownership when it is already connected.
    func setUp() {
        session == nil ? connect() : confirmWallet()
    }

    private func reset() {
        stored = Stored()
        cancel()
    }

    // MARK: Plumbing

    private func readySession(resume label: String, _ action: @escaping () -> Void) -> PhantomSession? {
        if let session, isReady(for: api.user) { return session }
        resume = (label, action)
        setUp()
        return nil
    }

    private func run(_ title: String, _ message: String, _ work: @escaping () async throws -> Void) {
        activity = WalletActivity(title: title, phase: .progress(message))
        Task {
            do { try await work() } catch { fail(error) }
        }
    }

    private func request(_ method: PhantomLink.Method, _ payload: [String: String], _ session: PhantomSession) throws {
        let url = try PhantomLink.request(base: base, method, payload: payload, session: session)
        activity?.phase = .waiting
        open(url)
    }

    private func progress(_ message: String) { activity?.phase = .progress(message) }
    private func succeed(_ message: String) { activity?.phase = .success(message) }
    private func fail(_ message: String) {
        stored.operation = nil
        resume = nil
        activity = WalletActivity(title: activity?.title ?? "Phantom", phase: .failure(message))
    }
    private func fail(_ error: Error) { fail(error.localizedDescription) }

    private func open(_ url: URL) {
        lastRequest = url
        Task {
            #if targetEnvironment(simulator)
            if Self.testWallet != nil { return await relay(url) }
            #endif
            // Phantom owns this universal link; without the app installed nothing can answer the request.
            let opened = await UIApplication.shared.open(url, options: [.universalLinksOnly: true])
            if !opened { fail(WalletError.phantomMissing) }
        }
    }

    #if targetEnvironment(simulator)
    /// Phantom cannot be installed in the simulator. With EVENTLY_TEST_WALLET set, requests go over HTTP to the
    /// stand-in wallet from ios/Tests/fake-phantom.rb, which answers with the same redirect Phantom would open.
    private static let testWallet = ProcessInfo.processInfo.environment["EVENTLY_TEST_WALLET"].flatMap(URL.init)
    private static let rpcEndpoint = ProcessInfo.processInfo.environment["EVENTLY_TEST_RPC"].flatMap(URL.init) ?? SolanaRPC.devnet
    private var base: URL { Self.testWallet ?? PhantomLink.universalLink }

    private func relay(_ url: URL) async {
        final class KeepRedirect: NSObject, URLSessionTaskDelegate {
            func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                            newRequest request: URLRequest) async -> URLRequest? { nil }
        }
        guard let (_, response) = try? await URLSession.shared.data(from: url, delegate: KeepRedirect()),
              let location = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location").flatMap(URL.init),
              handle(location) else { return fail("Тестовый кошелёк не ответил") }
    }
    #else
    private static let rpcEndpoint = SolanaRPC.devnet
    private var base: URL { PhantomLink.universalLink }
    #endif
}
