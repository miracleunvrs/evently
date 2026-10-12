import CryptoKit
import Foundation

// Phantom deeplink protocol and the Solana JSON-RPC calls the wallet flow needs. Foundation only, like SolanaKit.swift,
// so ios/Tests covers it on macOS.

struct PhantomSession: Codable, Equatable {
    /// Our X25519 key for this connection; Phantom encrypts its answers to it.
    let secretKey: Data
    let phantomPublicKey: Data
    let session: String
    let walletAddress: String
    /// Whether the connection asked Phantom for the Devnet cluster. Sessions saved before this field existed did.
    var devnet: Bool?
    var usesDevnet: Bool { devnet ?? true }
}

enum PhantomError: LocalizedError, Equatable {
    case cancelled
    case unauthorized
    /// Phantom's catch-all -32603: it could not process the request at all.
    case internalError
    case rejected(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .cancelled: "Действие отменено в Phantom"
        case .unauthorized: "Phantom больше не доверяет этому подключению. Подключи кошелёк заново"
        case .internalError: "Phantom не смог обработать запрос. Обнови Phantom и попробуй ещё раз"
        case .rejected(let message): "Phantom отклонил запрос: \(message)"
        case .invalidResponse: "Не удалось прочитать ответ Phantom"
        }
    }
}

enum PhantomLink {
    static let universalLink = URL(string: "https://phantom.app/ul/v1")!
    static let appURL = "https://evently-events.miracl3rk.chatgpt.site"
    static let scheme = "evently"

    enum Method: String, Codable {
        // signAndSendTransaction is deprecated by Phantom: the app asks for a signature and submits the transaction itself.
        case connect, signMessage, signTransaction
    }

    static func newSecretKey() -> Data { Curve25519.KeyAgreement.PrivateKey().rawRepresentation }

    static func publicKey(for secretKey: Data) throws -> Data {
        try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secretKey).publicKey.rawRepresentation
    }

    /// Which request a redirect such as `evently://phantom/connect?...` answers.
    static func method(of url: URL) -> Method? {
        guard url.scheme == scheme, url.host == "phantom" else { return nil }
        return Method(rawValue: url.lastPathComponent)
    }

    /// `devnet` asks Phantom to use Solana Devnet for this connection, which needs Testnet Mode switched on in Phantom.
    static func connect(base: URL = universalLink, secretKey: Data, devnet: Bool) throws -> URL {
        try url(base, .connect, [
            ("app_url", appURL),
            ("dapp_encryption_public_key", Base58.encode(publicKey(for: secretKey))),
            ("redirect_link", redirect(.connect))
        ] + (devnet ? [("cluster", "devnet")] : []))
    }

    /// A signing request; the payload travels encrypted with the session key.
    static func request(base: URL = universalLink, _ method: Method, payload: [String: String], session: PhantomSession) throws -> URL {
        var payload = payload
        payload["session"] = session.session
        var generator = SystemRandomNumberGenerator()
        let nonce = Data((0..<NaClBox.nonceLength).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        let key = try NaClBox.sharedKey(secretKey: session.secretKey, peerPublicKey: session.phantomPublicKey)
        let sealed = NaClBox.seal(try JSONSerialization.data(withJSONObject: payload), nonce: nonce, key: key)
        return try url(base, method, [
            ("dapp_encryption_public_key", Base58.encode(publicKey(for: session.secretKey))),
            ("nonce", Base58.encode(nonce)),
            ("redirect_link", redirect(method)),
            ("payload", Base58.encode(sealed))
        ])
    }

    static func session(from url: URL, secretKey: Data, devnet: Bool) throws -> PhantomSession {
        let query = try query(of: url)
        guard let phantomKey = query["phantom_encryption_public_key"].flatMap(Base58.decode), phantomKey.count == 32 else {
            throw PhantomError.invalidResponse
        }
        let data = try open(query, key: NaClBox.sharedKey(secretKey: secretKey, peerPublicKey: phantomKey))
        guard let address = data["public_key"], SolanaKey(base58: address) != nil, let session = data["session"] else {
            throw PhantomError.invalidResponse
        }
        return PhantomSession(secretKey: secretKey, phantomPublicKey: phantomKey, session: session, walletAddress: address, devnet: devnet)
    }

    static func response(from url: URL, session: PhantomSession) throws -> [String: String] {
        try open(query(of: url), key: NaClBox.sharedKey(secretKey: session.secretKey, peerPublicKey: session.phantomPublicKey))
    }

    private static func redirect(_ method: Method) -> String { "\(scheme)://phantom/\(method.rawValue)" }

    private static func url(_ base: URL, _ method: Method, _ items: [(String, String)]) throws -> URL {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let query = items.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "")" }.joined(separator: "&")
        guard var components = URLComponents(url: base.appendingPathComponent(method.rawValue), resolvingAgainstBaseURL: false) else {
            throw PhantomError.invalidResponse
        }
        components.percentEncodedQuery = query
        guard let url = components.url else { throw PhantomError.invalidResponse }
        return url
    }

    private static func query(of url: URL) throws -> [String: String] {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let query = Dictionary(items.compactMap { item in item.value.map { (item.name, $0) } }, uniquingKeysWith: { first, _ in first })
        if let code = query["errorCode"] {
            // 4001: the user declined. 4100: the session is no longer authorized.
            if code == "4001" { throw PhantomError.cancelled }
            if code == "4100" { throw PhantomError.unauthorized }
            if code == "-32603" { throw PhantomError.internalError }
            throw PhantomError.rejected(query["errorMessage"] ?? code)
        }
        return query
    }

    private static func open(_ query: [String: String], key: [UInt8]) throws -> [String: String] {
        guard let nonce = query["nonce"].flatMap(Base58.decode), let sealed = query["data"].flatMap(Base58.decode),
              let plain = NaClBox.open(sealed, nonce: nonce, key: key),
              let object = try? JSONSerialization.jsonObject(with: plain) as? [String: Any] else {
            throw PhantomError.invalidResponse
        }
        return object.compactMapValues { $0 as? String }
    }
}

enum SolanaRPCError: LocalizedError {
    case unavailable
    case failed(String)
    case transactionFailed
    case notLanded
    case expired
    case insufficientFunds

    var errorDescription: String? {
        switch self {
        case .unavailable: "Сеть Solana сейчас не отвечает. Попробуй ещё раз"
        case .failed(let message): "Ошибка сети Solana: \(message)"
        case .transactionFailed: "Транзакция не прошла в сети Solana"
        case .notLanded: "Транзакция не дошла до сети Solana. Попробуй ещё раз"
        case .expired: "Подпись заняла слишком много времени, и транзакция устарела. Попробуй ещё раз"
        case .insufficientFunds:
            "На кошельке не хватает тестовых SOL в сети Devnet. Их бесплатно выдаёт faucet.solana.com."
        }
    }
}

struct SolanaRPC {
    static let devnet = URL(string: "https://api.devnet.solana.com")!
    var endpoint = SolanaRPC.devnet

    private func call(_ method: String, _ params: [Any]) async throws -> Any {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params])
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SolanaRPCError.unavailable
        }
        if let error = body["error"] as? [String: Any] { throw SolanaRPCError.failed(error["message"] as? String ?? "RPC") }
        guard let result = body["result"] else { throw SolanaRPCError.unavailable }
        return result
    }

    private func value(_ result: Any) -> Any? { (result as? [String: Any])?["value"] }

    func latestBlockhash() async throws -> Data {
        let result = try await call("getLatestBlockhash", [["commitment": "confirmed"]])
        guard let text = (value(result) as? [String: Any])?["blockhash"] as? String,
              let hash = Base58.decode(text), hash.count == 32 else { throw SolanaRPCError.unavailable }
        return hash
    }

    func minimumBalance(space: UInt64) async throws -> UInt64 {
        guard let lamports = try await call("getMinimumBalanceForRentExemption", [space]) as? NSNumber else { throw SolanaRPCError.unavailable }
        return lamports.uint64Value
    }

    func balance(of address: String) async throws -> UInt64 {
        let result = try await call("getBalance", [address, ["commitment": "confirmed"]])
        guard let lamports = value(result) as? NSNumber else { throw SolanaRPCError.unavailable }
        return lamports.uint64Value
    }

    /// Submits a fully signed transaction and returns its signature.
    func send(_ transaction: Data) async throws -> String {
        do {
            let result = try await call("sendTransaction", [transaction.base64EncodedString(),
                                                           ["encoding": "base64", "preflightCommitment": "confirmed"]])
            guard let signature = result as? String else { throw SolanaRPCError.unavailable }
            return signature
        } catch SolanaRPCError.failed(let message) {
            if message.localizedCaseInsensitiveContains("blockhash not found") { throw SolanaRPCError.expired }
            if message.localizedCaseInsensitiveContains("insufficient") || message.localizedCaseInsensitiveContains("debit an account") {
                throw SolanaRPCError.insufficientFunds
            }
            throw SolanaRPCError.failed(message)
        }
    }

    /// nil while the network has not seen the signature yet; throws when the transaction failed.
    func isConfirmed(_ signature: String) async throws -> Bool? {
        let result = try await call("getSignatureStatuses", [[signature], ["searchTransactionHistory": true]])
        guard let status = (value(result) as? [Any])?.first as? [String: Any] else { return nil }
        if !(status["err"] is NSNull), status["err"] != nil { throw SolanaRPCError.transactionFailed }
        return ["confirmed", "finalized"].contains(status["confirmationStatus"] as? String ?? "")
    }

    /// Waits past the lifetime of a recent blockhash, after which an unseen transaction can no longer land.
    func waitForConfirmation(_ signature: String, timeout: TimeInterval = 80) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            do {
                if try await isConfirmed(signature) == true { return }
            } catch SolanaRPCError.transactionFailed {
                throw SolanaRPCError.transactionFailed
            } catch {
                // A flaky RPC answer is not a verdict; keep polling until the deadline.
            }
            guard Date() < deadline else { throw SolanaRPCError.notLanded }
            try await Task.sleep(nanoseconds: 1_500_000_000)
        }
    }
}
