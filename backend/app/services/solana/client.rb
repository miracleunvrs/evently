module Solana
  class Client
    DEFAULT_RPC = "https://api.devnet.solana.com".freeze

    def initialize(url: ENV.fetch("SOLANA_RPC_URL", DEFAULT_RPC), connection: nil)
      @connection = connection || Faraday.new(url: url) { |f| f.options.timeout = 12 }
    end

    def rpc(method, params = [])
      response = @connection.post do |request|
        request.headers["Content-Type"] = "application/json"
        request.body = { jsonrpc: "2.0", id: SecureRandom.uuid, method: method, params: params }.to_json
      end
      raise RpcError, "Solana RPC returned HTTP #{response.status}" unless response.success?

      body = JSON.parse(response.body)
      raise RpcError, body.dig("error", "message") || "Solana RPC error" if body["error"]
      body["result"]
    rescue Faraday::Error, JSON::ParserError => e
      raise RpcError, e.message
    end

    def transaction(signature)
      rpc("getTransaction", [ signature, { encoding: "jsonParsed", commitment: "confirmed", maxSupportedTransactionVersion: 0 } ])
    end

    def token_supply(mint)
      rpc("getTokenSupply", [ mint, { commitment: "confirmed" } ])
    end

    def token_accounts(owner, mint)
      rpc("getTokenAccountsByOwner", [ owner, { mint: mint }, { encoding: "jsonParsed", commitment: "confirmed" } ])
    end

    def mint_account(mint)
      rpc("getAccountInfo", [ mint, { encoding: "jsonParsed", commitment: "confirmed" } ])
    end
  end
end
