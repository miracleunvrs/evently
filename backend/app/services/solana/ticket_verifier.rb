module Solana
  class TicketVerifier
    TOKEN_2022_PROGRAM = Ticket::TOKEN_2022_PROGRAM

    def initialize(ticket, client: Client.new)
      @ticket = ticket
      @client = client
    end

    def verify!(signature:, token_address:)
      transaction = @client.transaction(signature)
      raise RpcError, "transaction is not confirmed" unless transaction
      raise RpcError, "transaction failed" if transaction.dig("meta", "err")

      keys = Array(transaction.dig("transaction", "message", "accountKeys"))
      signer_keys = keys.filter_map { |entry| entry.is_a?(Hash) && entry["signer"] ? entry["pubkey"] : nil }
      all_keys = keys.map { |entry| entry.is_a?(Hash) ? entry["pubkey"] : entry }
      raise RpcError, "wallet did not sign transaction" unless signer_keys.include?(@ticket.wallet_address)
      raise RpcError, "mint is not part of transaction" unless all_keys.include?(token_address)

      expected_memo = "evently:v1:#{@ticket.event.id}:#{@ticket.registration_id}"
      raise RpcError, "ticket memo does not match registration" unless Memo.matches?(transaction, expected_memo)

      mint = @client.mint_account(token_address)
      raise RpcError, "mint does not exist" unless mint&.dig("value")
      raise RpcError, "mint is not Token-2022" unless mint.dig("value", "owner") == TOKEN_2022_PROGRAM

      mint_info = mint.dig("value", "data", "parsed", "info") || {}
      extensions = Array(mint_info["extensions"]).filter_map { |extension| extension["extension"] }
      raise RpcError, "ticket mint is transferable" unless extensions.include?("nonTransferable")
      raise RpcError, "ticket mint authority is still active" if mint_info["mintAuthority"].present?

      supply = @client.token_supply(token_address)&.dig("value")
      raise RpcError, "ticket supply must equal one" unless supply&.fetch("amount", nil) == "1" && supply["decimals"] == 0

      accounts = Array(@client.token_accounts(@ticket.wallet_address, token_address)&.dig("value"))
      owns_one = accounts.any? do |account|
        info = account.dig("account", "data", "parsed", "info") || {}
        info["mint"] == token_address && info.dig("tokenAmount", "amount") == "1"
      end
      raise RpcError, "wallet does not own ticket" unless owns_one

      true
    end
  end
end
