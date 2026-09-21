module Solana
  class WalletSignature
    def self.valid?(wallet_address:, message:, signature:)
      public_key = Base58.base58_to_binary(wallet_address, :bitcoin)
      signature_bytes = Base64.strict_decode64(signature)
      return false unless public_key.bytesize == 32 && signature_bytes.bytesize == 64

      RbNaCl::VerifyKey.new(public_key).verify(signature_bytes, message)
      true
    rescue ArgumentError, RbNaCl::BadSignatureError
      false
    end
  end
end
