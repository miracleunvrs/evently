require "test_helper"

class SolanaWalletSignatureTest < ActiveSupport::TestCase
  test "verifies Phantom-compatible ed25519 signature" do
    signing_key = RbNaCl::Signatures::Ed25519::SigningKey.generate
    wallet = Base58.binary_to_base58(signing_key.verify_key.to_bytes, :bitcoin)
    message = "Evently wallet verification"
    signature = Base64.strict_encode64(signing_key.sign(message))

    assert Solana::WalletSignature.valid?(wallet_address: wallet, message: message, signature: signature)
    assert_not Solana::WalletSignature.valid?(wallet_address: wallet, message: "changed", signature: signature)
  end
end
