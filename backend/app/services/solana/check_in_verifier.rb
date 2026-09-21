module Solana
  class CheckInVerifier
    def initialize(organizer, client: Client.new)
      @organizer = organizer
      @client = client
    end

    def verify!(signature:, memo:)
      transaction = @client.transaction(signature)
      raise RpcError, "check-in transaction is not confirmed" unless transaction
      raise RpcError, "check-in transaction failed" if transaction.dig("meta", "err")

      keys = Array(transaction.dig("transaction", "message", "accountKeys"))
      signer_keys = keys.filter_map { |entry| entry.is_a?(Hash) && entry["signer"] ? entry["pubkey"] : nil }
      raise RpcError, "organizer wallet did not sign check-in" unless signer_keys.include?(@organizer.wallet_address)

      logs = Array(transaction.dig("meta", "logMessages")).join("\n")
      raise RpcError, "check-in memo does not match ticket" unless logs.include?(memo)

      true
    end
  end
end
