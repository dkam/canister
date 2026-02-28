class Screenshot < ApplicationRecord
  belongs_to :scene
  has_one_attached :image
end
