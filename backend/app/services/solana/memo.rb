module Solana
  module Memo
    PROGRAM_ID = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr".freeze

    def self.matches?(transaction, expected)
      Array(transaction.dig("transaction", "message", "instructions")).any? do |instruction|
        instruction["programId"] == PROGRAM_ID && instruction["parsed"] == expected
      end
    end
  end
end
