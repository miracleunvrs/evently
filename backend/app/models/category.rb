class Category < ApplicationRecord
  has_many :events, dependent: :nullify
  validates :slug, :title, presence: true, uniqueness: true
end
