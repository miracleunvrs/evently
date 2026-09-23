class Event < ApplicationRecord
  STATUSES = %w[draft published hidden].freeze
  COVER_URLS = %w[
    /covers/01-future-work.jpg
    /covers/02-after-dark.jpg
    /covers/03-creative-play.jpg
  ].freeze

  before_validation :assign_random_cover, on: :create

  belongs_to :organizer, class_name: "User"
  belongs_to :category, optional: true
  has_many :registrations, dependent: :destroy
  has_many :tickets, through: :registrations
  has_many :favorites, dependent: :destroy

  validates :title, presence: true, length: { maximum: 255 }
  validates :capacity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 5000 }
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }

  validate :valid_start_time, if: -> { new_record? || will_save_change_to_starts_at? }
  validate :capacity_covers_registrations, if: :will_save_change_to_capacity?

  def ended?
    starts_at.present? && Time.iso8601(starts_at) <= Time.current
  rescue ArgumentError
    true
  end

  def occupied
    registrations.where(status: "confirmed").count
  end

  private

  def valid_start_time
    Time.iso8601(starts_at.to_s)
  rescue ArgumentError
    errors.add(:starts_at, "must be an ISO 8601 date and time")
  end

  def capacity_covers_registrations
    errors.add(:capacity, "cannot be lower than confirmed registrations") if persisted? && capacity && capacity < occupied
  end

  def assign_random_cover
    self.cover_url = COVER_URLS.sample if cover_url.blank?
  end
end
