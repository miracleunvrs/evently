# A stand-in for the Phantom app, for end-to-end runs in the iOS Simulator where Phantom cannot be installed.
#
# It speaks Phantom's deeplink protocol over HTTP: the app (started with EVENTLY_TEST_WALLET=http://localhost:4810/ul/v1)
# sends the request it would open in Phantom and gets back the redirect Phantom would open. Messages are signed and
# transactions are really sent to Solana Devnet with a throwaway wallet, so the Rails API verifies them for real.
# Encryption is libsodium (RbNaCl), independent of the Swift implementation under test.
#
#   docker run --rm -d --name evently-fake-phantom -p 4810:4810 --volumes-from evently-api-1 \
#     -v "$PWD/ios/Tests:/tests:ro" -w /app evently-api bundle exec ruby /tests/fake-phantom.rb
#
# GET /control?reject=1 makes the next request come back declined, like a user tapping Cancel in Phantom.
# GET /control?wallet=2 switches to another wallet, like changing the account inside Phantom.
# GET /control?testnet_mode=0 makes requests on a Devnet connection fail with Phantom's internal error (-32603).
#
# With MOCK_CHAIN=1 nothing reaches Solana: transactions are kept in memory and this process also answers the
# JSON-RPC calls the app and the API make (point EVENTLY_TEST_RPC and the API's SOLANA_RPC_URL at it). That covers
# the app's flow when no test SOL is available; simulate-devnet.py covers the transaction itself on the real cluster.
require "base58"
require "base64"
require "digest"
require "json"
require "net/http"
require "rbnacl"
require "securerandom"
require "socket"
require "uri"

RPC = URI(ENV.fetch("SOLANA_RPC_URL", "https://api.devnet.solana.com"))
KEY_FILE = ENV.fetch("WALLET_KEY_FILE", "/tmp/fake-phantom-wallet.key")
PORT = Integer(ENV.fetch("PORT", "4810"))
LAMPORTS = 1_000_000_000
MOCK_CHAIN = ENV["MOCK_CHAIN"] == "1"
TOKEN_2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb".freeze
MEMO = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr".freeze

def b58(bytes) = Base58.binary_to_base58(bytes.b, :bitcoin)
def unb58(text) = Base58.base58_to_binary(text, :bitcoin)

def rpc(method, params)
  response = Net::HTTP.post(RPC, { jsonrpc: "2.0", id: 1, method: method, params: params }.to_json, "Content-Type" => "application/json")
  body = JSON.parse(response.body)
  raise body.dig("error", "message") || "RPC error" if body["error"]
  body["result"]
end

File.binwrite(KEY_FILE, RbNaCl::Random.random_bytes(32)) unless File.exist?(KEY_FILE)
SEED = File.binread(KEY_FILE)
BOX_KEY = RbNaCl::PrivateKey.generate
SESSIONS = {}
STATE = { reject: false, wallet: 0, testnet_mode: true }

def wallet = RbNaCl::SigningKey.new(STATE[:wallet].zero? ? SEED : Digest::SHA256.digest("#{SEED}#{STATE[:wallet]}"))
def address = b58(wallet.verify_key.to_bytes)

# Kept on disk so the mock chain survives a restart of this process.
SENT_FILE = "#{KEY_FILE}.sent"
SENT = File.exist?(SENT_FILE) ? Marshal.load(File.binread(SENT_FILE)) : {}

def balance = MOCK_CHAIN ? LAMPORTS : rpc("getBalance", [ address, { commitment: "confirmed" } ]).fetch("value")

def fund
  return if balance >= LAMPORTS / 20
  rpc("requestAirdrop", [ address, LAMPORTS ])
  30.times { sleep 1; break if balance >= LAMPORTS / 20 }
rescue StandardError => error
  warn "airdrop failed: #{error.message}"
end

def sealed(dapp_key, fields)
  nonce = RbNaCl::Random.random_bytes(24)
  box = RbNaCl::Box.new(RbNaCl::PublicKey.new(dapp_key), BOX_KEY).encrypt(nonce, fields.to_json)
  { nonce: b58(nonce), data: b58(box) }
end

def payload(params)
  dapp_key = unb58(params.fetch("dapp_encryption_public_key"))
  plain = RbNaCl::Box.new(RbNaCl::PublicKey.new(dapp_key), BOX_KEY).decrypt(unb58(params.fetch("nonce")), unb58(params.fetch("payload")))
  fields = JSON.parse(plain)
  session = SESSIONS[fields["session"]]
  raise KeyError, "unknown session" unless session && session[:key] == dapp_key
  raise InternalError if session[:devnet] && !STATE[:testnet_mode]
  [ dapp_key, fields ]
end

InternalError = Class.new(StandardError)

# Signs as the fee payer (the first account of the message). Like Phantom's signTransaction, it does not submit.
def sign(wire)
  count = wire.getbyte(0)
  message = wire.byteslice(1 + 64 * count..)
  raise "fee payer is not this wallet" unless message.byteslice(4, 32) == wallet.verify_key.to_bytes
  wire[1, 64] = wallet.sign(message)
  wire
end

# The mock chain's sendTransaction: every signer must have signed, then the transaction counts as confirmed.
def accept(wire)
  count = wire.getbyte(0)
  message = wire.byteslice(1 + 64 * count..)
  count.times do |index|
    RbNaCl::VerifyKey.new(message.byteslice(4 + 32 * index, 32)).verify(wire.byteslice(1 + 64 * index, 64), message)
  end
  b58(wire.byteslice(1, 64)).tap do |signature|
    SENT[signature] = decode(message)
    File.binwrite(SENT_FILE, Marshal.dump(SENT))
  end
end

# Reads a legacy transaction message into the shape of a jsonParsed getTransaction answer.
def decode(message)
  bytes = message.bytes
  compact = lambda do
    value = shift = 0
    loop do
      byte = bytes.shift
      value |= (byte & 0x7f) << shift
      break value if byte & 0x80 == 0
      shift += 7
    end
  end
  signers, readonly_signed, readonly_unsigned = bytes.shift(3)
  keys = Array.new(compact.call) { b58(bytes.shift(32).pack("C*")) }
  bytes.shift(32)
  accounts = keys.each_with_index.map do |key, index|
    signer = index < signers
    { "pubkey" => key, "signer" => signer, "writable" => signer ? index < signers - readonly_signed : index < keys.size - readonly_unsigned }
  end
  instructions = Array.new(compact.call) do
    program = keys[bytes.shift]
    used = Array.new(compact.call) { keys[bytes.shift] }
    data = bytes.shift(compact.call).pack("C*")
    { "programId" => program, "accounts" => used, "data" => data }
  end
  { "accounts" => accounts, "instructions" => instructions }
end

# The mint a stored ticket transaction creates: non-transferable, one token minted, mint authority dropped.
def minted(address)
  SENT.values.find do |transaction|
    token = transaction["instructions"].select { |item| item["programId"] == TOKEN_2022 && item["accounts"].first == address }.map { |item| item["data"].bytes }
    token.include?([ 32 ]) && token.include?([ 7, 1, 0, 0, 0, 0, 0, 0, 0 ]) && token.include?([ 6, 0, 0 ])
  end
end

def mock_rpc(method, params)
  context = { slot: 1 }
  case method
  when "getLatestBlockhash" then { context: context, value: { blockhash: b58(RbNaCl::Random.random_bytes(32)), lastValidBlockHeight: 1000 } }
  when "getMinimumBalanceForRentExemption" then 1_513_840
  when "getBalance" then { context: context, value: LAMPORTS }
  when "sendTransaction" then accept(Base64.decode64(params[0]))
  when "getSignatureStatuses" then { context: context, value: params[0].map { |signature| SENT[signature] && { slot: 1, err: nil, confirmationStatus: "confirmed" } } }
  when "getTransaction"
    transaction = SENT[params[0]] or return nil
    instructions = transaction["instructions"].map do |item|
      item["programId"] == MEMO ? { programId: MEMO, parsed: item["data"].force_encoding("UTF-8") } : { programId: item["programId"], accounts: item["accounts"] }
    end
    { slot: 1, meta: { err: nil }, transaction: { message: { accountKeys: transaction["accounts"], instructions: instructions } } }
  when "getAccountInfo"
    value = minted(params[0]) && { owner: TOKEN_2022, data: { parsed: { info: { mintAuthority: nil, extensions: [ { extension: "nonTransferable", state: {} } ] } } } }
    { context: context, value: value }
  when "getTokenSupply" then { context: context, value: { amount: minted(params[0]) ? "1" : "0", decimals: 0 } }
  when "getTokenAccountsByOwner"
    mint = params[1].fetch("mint")
    owned = minted(mint)&.dig("accounts", 0, "pubkey") == params[0]
    { context: context, value: owned ? [ { account: { data: { parsed: { info: { mint: mint, tokenAmount: { amount: "1" } } } } } } ] : [] }
  else raise "mock chain has no #{method}"
  end
end

def answer(path, params)
  redirect = params.fetch("redirect_link")
  if STATE[:reject]
    STATE[:reject] = false
    return "#{redirect}?#{URI.encode_www_form(errorCode: 4001, errorMessage: "User rejected the request.")}"
  end
  fields =
    case path
    when "/ul/v1/connect"
      dapp_key = unb58(params.fetch("dapp_encryption_public_key"))
      session = SecureRandom.hex(16)
      SESSIONS[session] = { key: dapp_key, devnet: params["cluster"] == "devnet" }
      sealed(dapp_key, { public_key: address, session: session }).merge(phantom_encryption_public_key: b58(BOX_KEY.public_key.to_bytes))
    when "/ul/v1/signMessage"
      dapp_key, request = payload(params)
      sealed(dapp_key, { signature: b58(wallet.sign(unb58(request.fetch("message")))) })
    when "/ul/v1/signTransaction"
      dapp_key, request = payload(params)
      sealed(dapp_key, { transaction: b58(sign(unb58(request.fetch("transaction")))) })
    else
      raise "unknown method #{path}"
    end
  "#{redirect}?#{URI.encode_www_form(fields)}"
rescue KeyError, RbNaCl::CryptoError
  "#{redirect}?#{URI.encode_www_form(errorCode: 4100, errorMessage: "The requested method and/or account has not been authorized by the user.")}"
rescue InternalError
  "#{redirect}?#{URI.encode_www_form(errorCode: -32603, errorMessage: "Unexpected error")}"
rescue StandardError => error
  "#{redirect}?#{URI.encode_www_form(errorCode: -32603, errorMessage: error.message)}"
end

fund unless MOCK_CHAIN
$stdout.sync = true
puts "fake Phantom on :#{PORT}, wallet #{address}, #{MOCK_CHAIN ? "mock chain" : "balance #{balance.fdiv(LAMPORTS)} SOL"}"
server = TCPServer.new("0.0.0.0", PORT)
loop do
  client = server.accept
  line = client.gets.to_s
  length = 0
  while (header = client.gets) && header != "\r\n"
    length = header.split(":", 2).last.to_i if header.downcase.start_with?("content-length:")
  end
  path, query = line.split[1].to_s.split("?", 2)
  params = URI.decode_www_form(query.to_s).to_h
  if line.start_with?("POST") && MOCK_CHAIN
    call = JSON.parse(client.read(length))
    body = { jsonrpc: "2.0", id: call["id"], result: mock_rpc(call["method"], call["params"] || []) }.to_json
    puts "rpc #{call["method"]}"
    client.write "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
  elsif path == "/control"
    STATE[:reject] = params["reject"] == "1"
    STATE[:wallet] = params["wallet"].to_i if params["wallet"]
    STATE[:testnet_mode] = params["testnet_mode"] != "0" if params["testnet_mode"]
    client.write "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
  elsif path == "/wallet"
    body = { address: address, lamports: balance }.to_json
    client.write "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
  else
    location = answer(path, params)
    puts "#{path} -> #{location.split("?").first}#{location.include?("errorCode") ? " (#{URI.decode_www_form(location.split("?", 2).last).to_h.values_at("errorCode", "errorMessage").join(": ")})" : ""}"
    client.write "HTTP/1.1 302 Found\r\nLocation: #{location}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
  end
  client.close
rescue StandardError => error
  warn "request failed: #{error.message}"
  client&.close
end
