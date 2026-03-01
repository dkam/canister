class Performer < ApplicationRecord
  include Filterable

  has_and_belongs_to_many :scenes
  has_and_belongs_to_many :galleries

  validate :image_exists

  scoped_search on: [:name, :birthdate, :ethnicity]

  default_scope { order(name: :asc) }
  scope :filter_favorites, ->(favorite) { where(favorite: favorite) }

  def age(date: Date.today)
    a = date.year - birthdate.year
    a -= 1 if birthdate.month > date.month || (birthdate.month >= date.month && birthdate.day > date.day)
    a
  end

  private

  def image_exists
    errors.add(:image, "is empty") unless image
  end
end
