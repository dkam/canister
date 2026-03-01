class Studio < ApplicationRecord
  has_one_attached :image
  has_many :scenes

  scoped_search on: [:name]

  validates :name, presence: true, uniqueness: true
  validate :image_attached

  private

  def image_attached
    errors.add(:image, "is empty") unless image.attached?
  end
end
