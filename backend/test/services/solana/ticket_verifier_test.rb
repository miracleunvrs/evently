require "test_helper"

class SolanaTicketVerifierTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:wallet, :mint, :event_id, :registration_id, :failed, keyword_init: true) do
    def transaction(_signature)
      {
        "meta" => { "err" => failed ? { "InstructionError" => [ 0, "error" ] } : nil, "logMessages" => [ "Program log: Memo (len 18): evently:v1:#{event_id}:#{registration_id}" ] },
        "transaction" => { "message" => { "instructions" => [ { "programId" => Solana::Memo::PROGRAM_ID, "parsed" => "evently:v1:#{event_id}:#{registration_id}" } ], "accountKeys" => [
          { "pubkey" => wallet, "signer" => true },
          { "pubkey" => mint, "signer" => false }
        ] } }
      }
    end

    def mint_account(_mint)
      {
        "value" => {
          "owner" => Ticket::TOKEN_2022_PROGRAM,
          "data" => {
            "parsed" => {
              "info" => {
                "mintAuthority" => nil,
                "extensions" => [ { "extension" => "nonTransferable", "state" => {} } ]
              }
            }
          }
        }
      }
    end

    def token_supply(_mint)
      { "value" => { "amount" => "1", "decimals" => 0 } }
    end

    def token_accounts(_owner, _mint)
      { "value" => [ { "account" => { "data" => { "parsed" => { "info" => { "mint" => mint, "tokenAmount" => { "amount" => "1" } } } } } } ] }
    end
  end

  test "verifies signer memo Token-2022 mint supply and owner" do
    wallet = "7xKsP91a111111111111111111111111111111111"
    mint = "9Mint111111111111111111111111111111111111"
    event = Struct.new(:id).new(25)
    registration = Struct.new(:event, :id).new(event, 481)
    ticket = Struct.new(:wallet_address, :event, :registration_id).new(wallet, event, registration.id)
    client = FakeClient.new(wallet: wallet, mint: mint, event_id: event.id, registration_id: registration.id, failed: false)

    assert Solana::TicketVerifier.new(ticket, client: client).verify!(signature: "signature", token_address: mint)
  end

  test "rejects failed transaction" do
    wallet = "7xKsP91a111111111111111111111111111111111"
    mint = "9Mint111111111111111111111111111111111111"
    event = Struct.new(:id).new(25)
    ticket = Struct.new(:wallet_address, :event, :registration_id).new(wallet, event, 481)
    client = FakeClient.new(wallet: wallet, mint: mint, event_id: 25, registration_id: 481, failed: true)

    assert_raises(Solana::RpcError) { Solana::TicketVerifier.new(ticket, client: client).verify!(signature: "signature", token_address: mint) }
  end

  test "rejects Token-2022 mint without non-transferable extension" do
    wallet = "7xKsP91a111111111111111111111111111111111"
    mint = "9Mint111111111111111111111111111111111111"
    event = Struct.new(:id).new(25)
    ticket = Struct.new(:wallet_address, :event, :registration_id).new(wallet, event, 481)
    client = FakeClient.new(wallet: wallet, mint: mint, event_id: 25, registration_id: 481, failed: false)
    client.define_singleton_method(:mint_account) do |_address|
      {
        "value" => {
          "owner" => Ticket::TOKEN_2022_PROGRAM,
          "data" => { "parsed" => { "info" => { "mintAuthority" => nil, "extensions" => [] } } }
        }
      }
    end

    error = assert_raises(Solana::RpcError) do
      Solana::TicketVerifier.new(ticket, client: client).verify!(signature: "signature", token_address: mint)
    end
    assert_equal "ticket mint is transferable", error.message
  end
end
