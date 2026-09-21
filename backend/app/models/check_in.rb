class CheckIn < ApplicationRecord
  belongs_to :ticket
  belongs_to :event
  belongs_to :checked_by, class_name: "User", optional: true
  validates :result, inclusion: { in: %w[ok duplicate] }
end
