require "test_helper"

class SolanaCheckInVerifierTest < ActiveSupport::TestCase
  FakeClient = Struct.new(:wallet, :memo, keyword_init: true) do
    def transaction(_signature)
      {
        "meta" => { "err" => nil, "logMessages" => [ "Program log: Memo: #{memo}" ] },
        "transaction" => { "message" => { "instructions" => [ { "programId" => Solana::Memo::PROGRAM_ID, "parsed" => memo } ], "accountKeys" => [ { "pubkey" => wallet, "signer" => true } ] } }
      }
    end
  end

  test "verifies organizer signer and ticket-specific memo" do
    organizer = Struct.new(:wallet_address).new("7xKsP91a111111111111111111111111111111111")
    memo = "evently:checkin:v1:42:481"
    client = FakeClient.new(wallet: organizer.wallet_address, memo: memo)

    assert Solana::CheckInVerifier.new(organizer, client: client).verify!(signature: "signature", memo: memo)
  end

  test "rejects ticket ID prefixes and spoofed log messages" do
    organizer = Struct.new(:wallet_address).new("7xKsP91a111111111111111111111111111111111")
    memo = "evently:checkin:v1:42:481"
    client = FakeClient.new(wallet: organizer.wallet_address, memo: "#{memo}0")
    assert_raises(Solana::RpcError) { Solana::CheckInVerifier.new(organizer, client: client).verify!(signature: "signature", memo: memo) }
    transaction = client.transaction("signature")
    transaction["meta"]["logMessages"] = [ memo ]
    transaction["transaction"]["message"]["instructions"] = [ { "programId" => "untrusted-program", "parsed" => memo } ]
    assert_not Solana::Memo.matches?(transaction, memo)
  end

  test "rejects a memo for another ticket" do
    organizer = Struct.new(:wallet_address).new("7xKsP91a111111111111111111111111111111111")
    client = FakeClient.new(wallet: organizer.wallet_address, memo: "evently:checkin:v1:other")

    assert_raises(Solana::RpcError) do
      Solana::CheckInVerifier.new(organizer, client: client).verify!(signature: "signature", memo: "evently:checkin:v1:42:481")
    end
  end
end
