class Event < ApplicationRecord
  STATUSES = %w[draft published hidden].freeze

  belongs_to :organizer, class_name: "User"
  belongs_to :category, optional: true
  has_many :registrations, dependent: :destroy
  has_many :tickets, through: :registrations
  has_many :favorites, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }
  validates :capacity, numericality: { greater_than: 0, less_than_or_equal_to: 5000 }
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }

  def occupied
    registrations.where(status: "confirmed").count
  end
end
