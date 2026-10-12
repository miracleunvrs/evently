import CryptoKit
import Foundation

// Pure Solana and NaCl primitives for the Phantom flow. No UIKit, so ios/Tests can compile this file on macOS
// and check it against vectors from @solana/web3.js, @solana/spl-token and libsodium.

enum Base58 {
    private static let alphabet = Array("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz".utf8)
    private static let values: [UInt8: Int] = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })

    static func encode(_ data: Data) -> String {
        let bytes = [UInt8](data)
        let zeros = bytes.prefix { $0 == 0 }.count
        var digits: [UInt8] = []
        for byte in bytes.dropFirst(zeros) {
            var carry = Int(byte)
            for index in digits.indices {
                carry += Int(digits[index]) << 8
                digits[index] = UInt8(carry % 58)
                carry /= 58
            }
            while carry > 0 { digits.append(UInt8(carry % 58)); carry /= 58 }
        }
        let text = [UInt8](repeating: alphabet[0], count: zeros) + digits.reversed().map { alphabet[Int($0)] }
        return String(decoding: text, as: UTF8.self)
    }

    static func decode(_ text: String) -> Data? {
        let characters = Array(text.utf8)
        let zeros = characters.prefix { $0 == alphabet[0] }.count
        var bytes: [UInt8] = []
        for character in characters.dropFirst(zeros) {
            guard var carry = values[character] else { return nil }
            for index in bytes.indices {
                carry += Int(bytes[index]) * 58
                bytes[index] = UInt8(carry & 0xff)
                carry >>= 8
            }
            while carry > 0 { bytes.append(UInt8(carry & 0xff)); carry >>= 8 }
        }
        return Data([UInt8](repeating: 0, count: zeros) + bytes.reversed())
    }
}

/// Unsigned big integer on 32-bit limbs. Only what Poly1305 and the Ed25519 curve check need; not constant time,
/// which is fine because it never touches a long-term secret key.
struct BigUInt: Equatable {
    private(set) var limbs: [UInt32]

    init(_ value: UInt32 = 0) { limbs = value == 0 ? [] : [value] }

    init(littleEndian bytes: [UInt8]) {
        limbs = stride(from: 0, to: bytes.count, by: 4).map { start in
            bytes[start..<min(start + 4, bytes.count)].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        }
        trim()
    }

    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.endIndex
        while index > hex.startIndex {
            let start = hex.index(index, offsetBy: -2, limitedBy: hex.startIndex) ?? hex.startIndex
            bytes.append(UInt8(hex[start..<index], radix: 16) ?? 0)
            index = start
        }
        self.init(littleEndian: bytes)
    }

    private mutating func trim() { while limbs.last == 0 { limbs.removeLast() } }

    var bitWidth: Int { limbs.isEmpty ? 0 : limbs.count * 32 - limbs.last!.leadingZeroBitCount }

    func bit(_ index: Int) -> Bool { index / 32 < limbs.count && limbs[index / 32] >> UInt32(index % 32) & 1 == 1 }

    func littleEndianBytes(count: Int) -> [UInt8] {
        (0..<count).map { $0 / 4 < limbs.count ? UInt8(truncatingIfNeeded: limbs[$0 / 4] >> (8 * UInt32($0 % 4))) : 0 }
    }

    static func < (lhs: BigUInt, rhs: BigUInt) -> Bool {
        if lhs.limbs.count != rhs.limbs.count { return lhs.limbs.count < rhs.limbs.count }
        for index in lhs.limbs.indices.reversed() where lhs.limbs[index] != rhs.limbs[index] { return lhs.limbs[index] < rhs.limbs[index] }
        return false
    }

    static func + (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        var result = BigUInt()
        var carry: UInt64 = 0
        for index in 0..<max(lhs.limbs.count, rhs.limbs.count) {
            carry += UInt64(index < lhs.limbs.count ? lhs.limbs[index] : 0) + UInt64(index < rhs.limbs.count ? rhs.limbs[index] : 0)
            result.limbs.append(UInt32(truncatingIfNeeded: carry))
            carry >>= 32
        }
        if carry > 0 { result.limbs.append(UInt32(carry)) }
        return result
    }

    /// Requires lhs >= rhs.
    static func - (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        var result = BigUInt()
        var borrow: Int64 = 0
        for index in lhs.limbs.indices {
            var value = Int64(lhs.limbs[index]) - Int64(index < rhs.limbs.count ? rhs.limbs[index] : 0) - borrow
            borrow = value < 0 ? 1 : 0
            if value < 0 { value += 1 << 32 }
            result.limbs.append(UInt32(value))
        }
        result.trim()
        return result
    }

    static func * (lhs: BigUInt, rhs: BigUInt) -> BigUInt {
        guard !lhs.limbs.isEmpty, !rhs.limbs.isEmpty else { return BigUInt() }
        var product = [UInt32](repeating: 0, count: lhs.limbs.count + rhs.limbs.count)
        for (i, a) in lhs.limbs.enumerated() {
            var carry: UInt64 = 0
            for (j, b) in rhs.limbs.enumerated() {
                carry += UInt64(product[i + j]) + UInt64(a) * UInt64(b)
                product[i + j] = UInt32(truncatingIfNeeded: carry)
                carry >>= 32
            }
            product[i + rhs.limbs.count] = UInt32(carry)
        }
        var result = BigUInt()
        result.limbs = product
        result.trim()
        return result
    }

    func shiftedRight(_ bits: Int) -> BigUInt {
        let (whole, part) = (bits / 32, UInt32(bits % 32))
        guard whole < limbs.count else { return BigUInt() }
        var result = BigUInt()
        result.limbs = (whole..<limbs.count).map { index in
            let high = part > 0 && index + 1 < limbs.count ? limbs[index + 1] << (32 - part) : 0
            return limbs[index] >> part | high
        }
        result.trim()
        return result
    }

    func lowBits(_ bits: Int) -> BigUInt {
        var result = BigUInt()
        result.limbs = Array(limbs.prefix((bits + 31) / 32))
        if bits % 32 > 0, result.limbs.count == (bits + 31) / 32 { result.limbs[result.limbs.count - 1] &= (1 << UInt32(bits % 32)) - 1 }
        result.trim()
        return result
    }
}

/// Arithmetic modulo a prime of the form 2^bits - c.
struct PrimeField {
    let bits: Int
    let c: BigUInt
    let prime: BigUInt

    init(bits: Int, c: UInt32) {
        self.bits = bits
        self.c = BigUInt(c)
        var limbs = [UInt8](repeating: 0, count: bits / 8 + 1)
        limbs[bits / 8] = 1 << UInt8(bits % 8)
        prime = BigUInt(littleEndian: limbs) - BigUInt(c)
    }

    func reduce(_ value: BigUInt) -> BigUInt {
        var value = value
        while value.bitWidth > bits { value = value.shiftedRight(bits) * c + value.lowBits(bits) }
        return value < prime ? value : value - prime
    }
    func add(_ a: BigUInt, _ b: BigUInt) -> BigUInt { reduce(a + b) }
    func subtract(_ a: BigUInt, _ b: BigUInt) -> BigUInt { reduce(a + prime - b) }
    func multiply(_ a: BigUInt, _ b: BigUInt) -> BigUInt { reduce(a * b) }
    func power(_ base: BigUInt, _ exponent: BigUInt) -> BigUInt {
        var result = BigUInt(1)
        for index in (0..<exponent.bitWidth).reversed() {
            result = multiply(result, result)
            if exponent.bit(index) { result = multiply(result, base) }
        }
        return result
    }
}

enum Ed25519Curve {
    private static let field = PrimeField(bits: 255, c: 19)
    private static let d = BigUInt(hex: "52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3")
    private static let exponent = BigUInt(hex: "0ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffd")

    /// True when the 32 bytes decompress to a curve point: x² = (y² − 1) / (d·y² + 1) has a root.
    static func isOnCurve(_ bytes: Data) -> Bool {
        guard bytes.count == 32 else { return false }
        var encoded = [UInt8](bytes)
        encoded[31] &= 0x7f
        let y = BigUInt(littleEndian: encoded)
        guard y < field.prime else { return false }
        let y2 = field.multiply(y, y)
        let u = field.subtract(y2, BigUInt(1))
        let v = field.add(field.multiply(d, y2), BigUInt(1))
        let v3 = field.multiply(field.multiply(v, v), v)
        let v7 = field.multiply(field.multiply(v3, v3), v)
        let x = field.multiply(field.multiply(u, v3), field.power(field.multiply(u, v7), exponent))
        let check = field.multiply(v, field.multiply(x, x))
        return check == u || check == field.subtract(BigUInt(), u)
    }
}

/// NaCl `crypto_box` (X25519 + XSalsa20-Poly1305), the encryption Phantom deeplinks use.
enum NaClBox {
    static let nonceLength = 24
    private static let macLength = 16

    static func sharedKey(secretKey: Data, peerPublicKey: Data) throws -> [UInt8] {
        let secret = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: secretKey)
        let shared = try secret.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPublicKey))
        return shared.withUnsafeBytes { hsalsa20(key: Array($0), input: [UInt8](repeating: 0, count: 16)) }
    }

    static func seal(_ message: Data, nonce: Data, key: [UInt8]) -> Data {
        let stream = xsalsa20(length: 32 + message.count, nonce: [UInt8](nonce), key: key)
        let cipher = zip(message, stream.dropFirst(32)).map { $0 ^ $1 }
        return Data(poly1305(cipher, key: Array(stream.prefix(32))) + cipher)
    }

    static func open(_ box: Data, nonce: Data, key: [UInt8]) -> Data? {
        guard box.count >= macLength, nonce.count == nonceLength else { return nil }
        let cipher = [UInt8](box.dropFirst(macLength))
        let stream = xsalsa20(length: 32 + cipher.count, nonce: [UInt8](nonce), key: key)
        let expected = poly1305(cipher, key: Array(stream.prefix(32)))
        guard zip(expected, box.prefix(macLength)).reduce(UInt8(0), { $0 | ($1.0 ^ $1.1) }) == 0 else { return nil }
        return Data(zip(cipher, stream.dropFirst(32)).map { $0 ^ $1 })
    }

    private static func word(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }

    /// Salsa20 state for a 32-byte key and 16 bytes of nonce/counter, after 20 rounds and before the final addition.
    private static func rounds(key: [UInt8], input: [UInt8]) -> (initial: [UInt32], mixed: [UInt32]) {
        let sigma = Array("expand 32-byte k".utf8)
        var x = [UInt32](repeating: 0, count: 16)
        for index in 0..<4 {
            x[index * 5] = word(sigma, index * 4)
            x[1 + index] = word(key, index * 4)
            x[11 + index] = word(key, 16 + index * 4)
            x[6 + index] = word(input, index * 4)
        }
        let initial = x
        func quarter(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
            func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 { value << count | value >> (32 - count) }
            x[b] ^= rotate(x[a] &+ x[d], 7)
            x[c] ^= rotate(x[b] &+ x[a], 9)
            x[d] ^= rotate(x[c] &+ x[b], 13)
            x[a] ^= rotate(x[d] &+ x[c], 18)
        }
        for _ in 0..<10 {
            quarter(0, 4, 8, 12); quarter(5, 9, 13, 1); quarter(10, 14, 2, 6); quarter(15, 3, 7, 11)
            quarter(0, 1, 2, 3); quarter(5, 6, 7, 4); quarter(10, 11, 8, 9); quarter(15, 12, 13, 14)
        }
        return (initial, x)
    }

    private static func bytes(_ words: [UInt32]) -> [UInt8] {
        words.flatMap { [UInt8(truncatingIfNeeded: $0), UInt8(truncatingIfNeeded: $0 >> 8), UInt8(truncatingIfNeeded: $0 >> 16), UInt8(truncatingIfNeeded: $0 >> 24)] }
    }

    private static func hsalsa20(key: [UInt8], input: [UInt8]) -> [UInt8] {
        let x = rounds(key: key, input: input).mixed
        return bytes([x[0], x[5], x[10], x[15], x[6], x[7], x[8], x[9]])
    }

    private static func xsalsa20(length: Int, nonce: [UInt8], key: [UInt8]) -> [UInt8] {
        let subkey = hsalsa20(key: key, input: Array(nonce.prefix(16)))
        var stream: [UInt8] = []
        var counter: UInt64 = 0
        while stream.count < length {
            let block = Array(nonce.suffix(8)) + (0..<8).map { UInt8(truncatingIfNeeded: counter >> (8 * UInt64($0))) }
            let state = rounds(key: subkey, input: block)
            stream += bytes(zip(state.initial, state.mixed).map { $0 &+ $1 })
            counter += 1
        }
        return Array(stream.prefix(length))
    }

    private static func poly1305(_ message: [UInt8], key: [UInt8]) -> [UInt8] {
        let field = PrimeField(bits: 130, c: 5)
        var clamped = Array(key.prefix(16))
        for index in [3, 7, 11, 15] { clamped[index] &= 15 }
        for index in [4, 8, 12] { clamped[index] &= 252 }
        let r = BigUInt(littleEndian: clamped)
        var accumulator = BigUInt()
        for start in stride(from: 0, to: message.count, by: 16) {
            let block = Array(message[start..<min(start + 16, message.count)]) + [1]
            accumulator = field.multiply(accumulator + BigUInt(littleEndian: block), r)
        }
        return (accumulator + BigUInt(littleEndian: Array(key[16..<32]))).littleEndianBytes(count: 16)
    }
}

struct SolanaKey: Hashable {
    let bytes: Data

    init?(bytes: Data) {
        guard bytes.count == 32 else { return nil }
        self.bytes = Data(bytes)
    }
    init?(base58: String) {
        guard let decoded = Base58.decode(base58) else { return nil }
        self.init(bytes: decoded)
    }
    private init(known base58: String) { bytes = Base58.decode(base58)! }

    var base58: String { Base58.encode(bytes) }

    static let systemProgram = SolanaKey(known: "11111111111111111111111111111111")
    static let token2022Program = SolanaKey(known: "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb")
    static let associatedTokenProgram = SolanaKey(known: "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL")
    static let memoProgram = SolanaKey(known: "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr")
    static let rentSysvar = SolanaKey(known: "SysvarRent111111111111111111111111111111111")

    /// Program-derived address: the first SHA-256 of the seeds (bump 255 downwards) that is not a curve point.
    static func programAddress(seeds: [Data], program: SolanaKey) -> SolanaKey? {
        for bump in (0...UInt8.max).reversed() {
            var hasher = SHA256()
            seeds.forEach { hasher.update(data: $0) }
            hasher.update(data: Data([bump]))
            hasher.update(data: program.bytes)
            hasher.update(data: Data("ProgramDerivedAddress".utf8))
            let candidate = Data(hasher.finalize())
            if !Ed25519Curve.isOnCurve(candidate) { return SolanaKey(bytes: candidate) }
        }
        return nil
    }

    static func associatedTokenAddress(owner: SolanaKey, mint: SolanaKey, tokenProgram: SolanaKey = .token2022Program) -> SolanaKey? {
        programAddress(seeds: [owner.bytes, tokenProgram.bytes, mint.bytes], program: .associatedTokenProgram)
    }
}

struct SolanaInstruction {
    struct Account {
        let key: SolanaKey
        var signer = false
        var writable = false
    }
    let program: SolanaKey
    let accounts: [Account]
    let data: Data
}

struct SolanaTransaction {
    let feePayer: SolanaKey
    let recentBlockhash: Data
    let instructions: [SolanaInstruction]

    /// Accounts in wire order: writable signers (fee payer first), readonly signers, writable, readonly.
    private var accounts: [SolanaInstruction.Account] {
        var merged = [SolanaInstruction.Account(key: feePayer, signer: true, writable: true)]
        let used = instructions.flatMap(\.accounts) + instructions.map { SolanaInstruction.Account(key: $0.program) }
        for account in used {
            if let index = merged.firstIndex(where: { $0.key == account.key }) {
                merged[index].signer = merged[index].signer || account.signer
                merged[index].writable = merged[index].writable || account.writable
            } else {
                merged.append(account)
            }
        }
        return merged.filter { $0.signer && $0.writable } + merged.filter { $0.signer && !$0.writable } +
            merged.filter { !$0.signer && $0.writable } + merged.filter { !$0.signer && !$0.writable }
    }

    var signers: [SolanaKey] { accounts.filter(\.signer).map(\.key) }

    var message: Data {
        let ordered = accounts
        var data = Data([UInt8(ordered.filter(\.signer).count),
                         UInt8(ordered.filter { $0.signer && !$0.writable }.count),
                         UInt8(ordered.filter { !$0.signer && !$0.writable }.count)])
        data += Self.compact(ordered.count)
        ordered.forEach { data += $0.key.bytes }
        data += recentBlockhash
        data += Self.compact(instructions.count)
        for instruction in instructions {
            data.append(UInt8(ordered.firstIndex { $0.key == instruction.program }!))
            data += Self.compact(instruction.accounts.count)
            instruction.accounts.forEach { account in data.append(UInt8(ordered.firstIndex { $0.key == account.key }!)) }
            data += Self.compact(instruction.data.count)
            data += instruction.data
        }
        return data
    }

    /// Wire format; a signer without a signature gets 64 zero bytes for the wallet to fill in.
    func serialized(signatures: [SolanaKey: Data] = [:]) -> Data {
        let required = signers
        var data = Self.compact(required.count)
        required.forEach { data += signatures[$0] ?? Data(count: 64) }
        return data + message
    }

    private static func compact(_ value: Int) -> Data {
        var value = value
        var data = Data()
        repeat {
            let byte = UInt8(value & 0x7f)
            value >>= 7
            data.append(value == 0 ? byte : byte | 0x80)
        } while value > 0
        return data
    }
}

/// The two transactions Evently needs, built exactly like lib/web3.ts builds them in the web client.
enum TicketTransaction {
    /// Token-2022 mint account with the NonTransferable extension.
    static let mintLength: UInt64 = 170

    static func memo(eventId: Int, registrationId: Int) -> String { "evently:v1:\(eventId):\(registrationId)" }

    static func mint(owner: SolanaKey, mint: SolanaKey, eventId: Int, registrationId: Int,
                     rentLamports: UInt64, recentBlockhash: Data) -> SolanaTransaction? {
        guard let tokenAccount = SolanaKey.associatedTokenAddress(owner: owner, mint: mint) else { return nil }
        typealias Account = SolanaInstruction.Account
        let token = SolanaKey.token2022Program
        return SolanaTransaction(feePayer: owner, recentBlockhash: recentBlockhash, instructions: [
            // System: create the mint account
            SolanaInstruction(program: .systemProgram,
                              accounts: [Account(key: owner, signer: true, writable: true), Account(key: mint, signer: true, writable: true)],
                              data: little(UInt32(0)) + little(rentLamports) + little(mintLength) + token.bytes),
            // Token-2022: InitializeNonTransferableMint
            SolanaInstruction(program: token, accounts: [Account(key: mint, writable: true)], data: Data([32])),
            // InitializeMint: 0 decimals, owner as mint authority, no freeze authority
            SolanaInstruction(program: token, accounts: [Account(key: mint, writable: true), Account(key: .rentSysvar)],
                              data: Data([0, 0]) + owner.bytes + Data([0])),
            // Associated token account, idempotent
            SolanaInstruction(program: .associatedTokenProgram,
                              accounts: [Account(key: owner, signer: true, writable: true), Account(key: tokenAccount, writable: true),
                                         Account(key: owner), Account(key: mint), Account(key: .systemProgram), Account(key: token)],
                              data: Data([1])),
            // MintTo: exactly one ticket
            SolanaInstruction(program: token,
                              accounts: [Account(key: mint, writable: true), Account(key: tokenAccount, writable: true), Account(key: owner, signer: true)],
                              data: Data([7]) + little(UInt64(1))),
            // SetAuthority(MintTokens → none): supply stays at one forever
            SolanaInstruction(program: token, accounts: [Account(key: mint, writable: true), Account(key: owner, signer: true)],
                              data: Data([6, 0, 0])),
            SolanaInstruction(program: .memoProgram, accounts: [Account(key: owner, signer: true), Account(key: mint)],
                              data: Data(memo(eventId: eventId, registrationId: registrationId).utf8))
        ])
    }

    static func checkIn(organizer: SolanaKey, memo: String, recentBlockhash: Data) -> SolanaTransaction {
        SolanaTransaction(feePayer: organizer, recentBlockhash: recentBlockhash, instructions: [
            SolanaInstruction(program: .memoProgram, accounts: [SolanaInstruction.Account(key: organizer, signer: true)], data: Data(memo.utf8))
        ])
    }

    private static func little<T: FixedWidthInteger>(_ value: T) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
