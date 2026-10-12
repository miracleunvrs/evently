import CryptoKit
import Foundation

// Checks SolanaKit.swift against ios/Tests/vectors.json. Run with ios/Tests/run.sh.

struct Vectors: Decodable {
    struct Encoded: Decodable { let hex: String; let base58: String }
    struct Curve: Decodable { let hex: String; let onCurve: Bool }
    struct Associated: Decodable { let owner: String; let mint: String; let address: String }
    struct Instruction: Decodable, Equatable {
        struct Key: Decodable, Equatable { let pubkey: String; let signer: Bool; let writable: Bool }
        let program: String; let keys: [Key]; let data: String
    }
    struct Ticket: Decodable {
        let owner: String; let mintSeed: String; let mint: String; let eventId: Int; let registrationId: Int
        let rent: UInt64; let mintLength: UInt64; let blockhash: String; let tokenAccount: String; let instructions: [Instruction]
    }
    struct CheckIn: Decodable { let organizer: String; let memo: String; let blockhash: String; let instructions: [Instruction] }
    struct Box: Decodable {
        let secretKey: String; let publicKey: String; let peerSecretKey: String; let peerPublicKey: String
        let nonce: String; let message: String; let box: String
    }
    let base58: [Encoded]; let onCurve: [Curve]; let associated: [Associated]; let ticket: Ticket; let checkIn: CheckIn; let box: [Box]
}

func data(_ hex: String) -> Data {
    var result = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        result.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return result
}
func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

var failures = 0
var checks = 0
func expect(_ condition: Bool, _ label: @autoclosure () -> String) {
    checks += 1
    if !condition { failures += 1; print("FAIL \(label())") }
}

/// Decodes the wire message back into instructions, the way a validator reads it.
func decode(message: Data) -> (signers: [String], instructions: [Vectors.Instruction]) {
    var bytes = [UInt8](message)[...]
    func take(_ count: Int) -> [UInt8] { defer { bytes = bytes.dropFirst(count) }; return Array(bytes.prefix(count)) }
    func compact() -> Int {
        var value = 0, shift = 0
        while true {
            let byte = Int(take(1)[0])
            value |= (byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
    }
    let header = take(3).map(Int.init)
    let keys = (0..<compact()).map { _ in Base58.encode(Data(take(32))) }
    _ = take(32)
    func signer(_ index: Int) -> Bool { index < header[0] }
    func writable(_ index: Int) -> Bool {
        signer(index) ? index < header[0] - header[1] : index < keys.count - header[2]
    }
    let instructions = (0..<compact()).map { _ -> Vectors.Instruction in
        let program = keys[Int(take(1)[0])]
        let accounts = (0..<compact()).map { _ in Int(take(1)[0]) }
        let payload = take(compact())
        return Vectors.Instruction(program: program,
                                   keys: accounts.map { .init(pubkey: keys[$0], signer: signer($0), writable: writable($0)) },
                                   data: hex(Data(payload)))
    }
    expect(bytes.isEmpty, "message has trailing bytes")
    return (Array(keys.prefix(header[0])), instructions)
}

// `--ticket-for <owner> <rent lamports>` prints a ticket transaction for that wallet, for simulate-devnet.py.
if let flag = CommandLine.arguments.firstIndex(of: "--ticket-for"), CommandLine.arguments.count > flag + 2 {
    let owner = SolanaKey(base58: CommandLine.arguments[flag + 1])!
    let key = Curve25519.Signing.PrivateKey()
    let mint = SolanaKey(bytes: key.publicKey.rawRepresentation)!
    let transaction = TicketTransaction.mint(owner: owner, mint: mint, eventId: 42, registrationId: 1337,
                                             rentLamports: UInt64(CommandLine.arguments[flag + 2])!, recentBlockhash: Data(count: 32))!
    let wire = transaction.serialized(signatures: [mint: try key.signature(for: transaction.message)])
    print([wire.base64EncodedString(), mint.base58, SolanaKey.associatedTokenAddress(owner: owner, mint: mint)!.base58,
           TicketTransaction.memo(eventId: 42, registrationId: 1337)].joined(separator: " "))
    exit(0)
}

let path = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "vectors.json"
let vectors = try JSONDecoder().decode(Vectors.self, from: Data(contentsOf: URL(fileURLWithPath: path)))

for item in vectors.base58 {
    expect(Base58.encode(data(item.hex)) == item.base58, "base58 encode \(item.hex)")
    expect(Base58.decode(item.base58) == data(item.hex), "base58 decode \(item.base58)")
}
expect(Base58.decode("0OIl") == nil, "base58 rejects characters outside the alphabet")

for item in vectors.onCurve {
    expect(Ed25519Curve.isOnCurve(data(item.hex)) == item.onCurve, "on-curve \(item.hex)")
}

for item in vectors.associated {
    let address = SolanaKey.associatedTokenAddress(owner: SolanaKey(base58: item.owner)!, mint: SolanaKey(base58: item.mint)!)
    expect(address?.base58 == item.address, "associated token address for \(item.owner)")
}

for item in vectors.box {
    let key = try NaClBox.sharedKey(secretKey: data(item.secretKey), peerPublicKey: data(item.peerPublicKey))
    let peerKey = try NaClBox.sharedKey(secretKey: data(item.peerSecretKey), peerPublicKey: data(item.publicKey))
    expect(key == peerKey, "box shared key is symmetric")
    expect(hex(NaClBox.seal(data(item.message), nonce: data(item.nonce), key: key)) == item.box, "box seal, \(item.message.count / 2) bytes")
    expect(NaClBox.open(data(item.box), nonce: data(item.nonce), key: peerKey) == data(item.message), "box open, \(item.message.count / 2) bytes")
    var forged = data(item.box)
    forged[forged.count - 1] ^= 1
    expect(NaClBox.open(forged, nonce: data(item.nonce), key: peerKey) == nil, "box rejects a forged ciphertext")
}
let wrongKey = try NaClBox.sharedKey(secretKey: data(vectors.box[1].secretKey), peerPublicKey: data(vectors.box[0].peerPublicKey))
expect(NaClBox.open(data(vectors.box[0].box), nonce: data(vectors.box[0].nonce), key: wrongKey) == nil, "box rejects the wrong key")

let ticket = vectors.ticket
let mintKey = try Curve25519.Signing.PrivateKey(rawRepresentation: data(ticket.mintSeed))
let mint = SolanaKey(bytes: mintKey.publicKey.rawRepresentation)!
expect(mint.base58 == ticket.mint, "mint public key")
expect(TicketTransaction.mintLength == ticket.mintLength, "mint account length")
let transaction = TicketTransaction.mint(owner: SolanaKey(base58: ticket.owner)!, mint: mint, eventId: ticket.eventId,
                                         registrationId: ticket.registrationId, rentLamports: ticket.rent,
                                         recentBlockhash: Base58.decode(ticket.blockhash)!)!
let decoded = decode(message: transaction.message)
expect(decoded.signers == [ticket.owner, ticket.mint], "ticket signers are owner (fee payer) then mint")
expect(decoded.instructions == ticket.instructions, "ticket instructions match @solana/spl-token")
let signature = try mintKey.signature(for: transaction.message)
let wire = transaction.serialized(signatures: [mint: signature])
expect(wire.count == 1 + 128 + transaction.message.count && wire[0] == 2, "ticket wire layout")
expect(wire[1..<65] == Data(count: 64), "fee payer signature is left for the wallet")
expect(mintKey.publicKey.isValidSignature(wire[65..<129], for: transaction.message), "mint signature verifies")
expect(wire.count <= 1232, "ticket transaction fits in one packet (\(wire.count) bytes)")

let checkIn = TicketTransaction.checkIn(organizer: SolanaKey(base58: vectors.checkIn.organizer)!, memo: vectors.checkIn.memo,
                                        recentBlockhash: Base58.decode(vectors.checkIn.blockhash)!)
let decodedCheckIn = decode(message: checkIn.message)
expect(decodedCheckIn.signers == [vectors.checkIn.organizer], "check-in signer is the organizer")
expect(decodedCheckIn.instructions == vectors.checkIn.instructions, "check-in instructions match @solana/web3.js")

// Phantom deeplinks: play Phantom's side with the box primitive already checked against libsodium above.
func query(_ url: URL) -> [String: String] {
    Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
}
func phantomRedirect(_ method: String, _ fields: [String: Any], key: [UInt8], extra: [String: String] = [:]) -> URL {
    let nonce = Data((0..<24).map { UInt8($0 * 7 + fields.count) })
    let sealed = NaClBox.seal(try! JSONSerialization.data(withJSONObject: fields), nonce: nonce, key: key)
    var components = URLComponents(string: "evently://phantom/\(method)")!
    components.queryItems = (["nonce": Base58.encode(nonce), "data": Base58.encode(sealed)].merging(extra) { $1 }).map { URLQueryItem(name: $0.key, value: $0.value) }
    return components.url!
}
let appSecret = PhantomLink.newSecretKey()
let phantomSecret = PhantomLink.newSecretKey()
let phantomPublic = try PhantomLink.publicKey(for: phantomSecret)
let connectURL = try PhantomLink.connect(secretKey: appSecret, devnet: true)
let connectQuery = query(connectURL)
expect(connectURL.absoluteString.hasPrefix("https://phantom.app/ul/v1/connect?"), "connect opens Phantom's universal link")
expect(connectQuery["cluster"] == "devnet" && connectQuery["redirect_link"] == "evently://phantom/connect", "connect asks for devnet and our redirect")
expect(connectURL.absoluteString.contains("redirect_link=evently%3A%2F%2Fphantom%2Fconnect"), "redirect link is percent-encoded")
let phantomKey = try NaClBox.sharedKey(secretKey: phantomSecret, peerPublicKey: Base58.decode(connectQuery["dapp_encryption_public_key"]!)!)
let connected = try PhantomLink.session(
    from: phantomRedirect("connect", ["public_key": ticket.owner, "session": "session-token"], key: phantomKey,
                          extra: ["phantom_encryption_public_key": Base58.encode(phantomPublic)]),
    secretKey: appSecret, devnet: true)
expect(!query(try PhantomLink.connect(secretKey: appSecret, devnet: false)).keys.contains("cluster"), "a plain connection leaves the cluster to Phantom")
expect(connected.usesDevnet, "the session remembers it asked for devnet")
expect(connected.walletAddress == ticket.owner && connected.session == "session-token" && connected.phantomPublicKey == phantomPublic, "connect answer becomes a session")
expect(PhantomLink.method(of: URL(string: "evently://phantom/signMessage?x=1")!) == .signMessage, "redirect names its request")
expect(PhantomLink.method(of: URL(string: "https://phantom/connect")!) == nil && PhantomLink.method(of: URL(string: "evently://other/connect")!) == nil, "foreign links are ignored")

let signURL = try PhantomLink.request(.signMessage, payload: ["message": Base58.encode(Data("hello".utf8))], session: connected)
let signQuery = query(signURL)
expect(signURL.path == "/ul/v1/signMessage" && signQuery["redirect_link"] == "evently://phantom/signMessage", "sign request path and redirect")
let payload = NaClBox.open(Base58.decode(signQuery["payload"]!)!, nonce: Base58.decode(signQuery["nonce"]!)!, key: phantomKey)
    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
expect(payload == ["message": Base58.encode(Data("hello".utf8)), "session": "session-token"], "Phantom can read the request payload")
expect(try PhantomLink.request(.signTransaction, payload: ["transaction": "tx"], session: connected).path == "/ul/v1/signTransaction", "transactions are only signed by Phantom")
let secondNonce = query(try PhantomLink.request(.signMessage, payload: [:], session: connected))["nonce"]
expect(secondNonce != signQuery["nonce"], "every request uses a fresh nonce")

let answer = try PhantomLink.response(from: phantomRedirect("signMessage", ["signature": "5sig"], key: phantomKey), session: connected)
expect(answer == ["signature": "5sig"], "signed answer is decrypted")
func failure(_ url: URL) -> PhantomError? {
    do { _ = try PhantomLink.response(from: url, session: connected); return nil } catch { return error as? PhantomError }
}
expect(failure(URL(string: "evently://phantom/signMessage?errorCode=4001&errorMessage=User%20rejected")!) == .cancelled, "a declined request is a cancellation")
expect(failure(URL(string: "evently://phantom/signMessage?errorCode=4100&errorMessage=Unauthorized")!) == .unauthorized, "a dead session is reported as such")
expect(failure(URL(string: "evently://phantom/signMessage?errorCode=-32603&errorMessage=Unexpected+error")!) == .internalError, "Phantom's internal error is told apart")
expect(failure(URL(string: "evently://phantom/signMessage?errorCode=-32000&errorMessage=Boom")!) == .rejected("Boom"), "other errors keep Phantom's message")
let strangerKey = try NaClBox.sharedKey(secretKey: PhantomLink.newSecretKey(), peerPublicKey: phantomPublic)
expect(failure(phantomRedirect("signMessage", ["signature": "5sig"], key: strangerKey)) == .invalidResponse, "an answer sealed with another key is rejected")

// Hex of both transactions for verify-transactions.mjs, which re-parses them with @solana/web3.js.
print("TICKET_TX \(hex(wire))")
print("CHECKIN_TX \(hex(checkIn.serialized()))")
print(failures == 0 ? "OK \(checks) checks" : "FAILED \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
