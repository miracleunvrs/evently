class Registration < ApplicationRecord
  STATUSES = %w[confirmed waitlisted cancelled].freeze

  belongs_to :event
  belongs_to :user
  has_one :ticket, dependent: :destroy

  validates :user_id, uniqueness: { scope: :event_id }
  validates :status, inclusion: { in: STATUSES }
end
