class Ticket < ApplicationRecord
  TOKEN_2022_PROGRAM = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb".freeze
  BLOCKCHAIN_STATUSES = %w[pending confirmed failed used].freeze

  belongs_to :registration
  has_one :event, through: :registration
  has_many :check_ins, dependent: :destroy

  validates :code, presence: true, uniqueness: true
  validates :registration_id, uniqueness: true
  validates :status, inclusion: { in: %w[active used] }
  validates :blockchain_status, inclusion: { in: BLOCKCHAIN_STATUSES }

  def explorer_url
    value = solana_signature.presence || token_address.presence
    return nil unless value

    kind = solana_signature.present? ? "tx" : "address"
    "https://explorer.solana.com/#{kind}/#{value}?cluster=devnet"
  end
end
