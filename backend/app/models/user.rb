class User < ApplicationRecord
  ROLES = %w[visitor organizer admin].freeze

  has_many :events, foreign_key: :organizer_id, dependent: :restrict_with_error
  has_many :registrations, dependent: :destroy
  has_many :tickets, through: :registrations
  has_many :favorites, dependent: :destroy

  validates :name, presence: true, length: { in: 2..80 }
  validates :email, presence: true, length: { maximum: 254 }, format: { with: URI::MailTo::EMAIL_REGEXP }, uniqueness: { case_sensitive: false }
  validates :password_hash, presence: true
  validates :role, inclusion: { in: ROLES }

  def password=(raw)
    self.password_hash = BCrypt::Password.create(raw)
  end

  def authenticate(raw)
    BCrypt::Password.new(password_hash).is_password?(raw) && self
  rescue BCrypt::Errors::InvalidHash
    false
  end
end
