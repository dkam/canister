class Screenshot < ApplicationRecord
  belongs_to :video
  has_one_attached :image
end
