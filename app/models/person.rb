class Person < ApplicationRecord
  include Filterable

  has_one_attached :image
  has_and_belongs_to_many :videos
  has_and_belongs_to_many :galleries

  attr_accessor :skip_image_validation
  validate :image_attached, unless: :skip_image_validation

  scoped_search on: [:name, :birthdate, :ethnicity]

  scope :filter_favorites, ->(favorite) { where(favorite: favorite) }

  def age(date: Date.today)
    a = date.year - birthdate.year
    a -= 1 if birthdate.month > date.month || (birthdate.month >= date.month && birthdate.day > date.day)
    a
  end

  private

  def image_attached
    errors.add(:image, "is empty") unless image.attached?
  end
end
