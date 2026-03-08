class Tag < ApplicationRecord
  has_many :taggings
  has_many :videos, through: :taggings, source: :taggable, source_type: "Video"

  has_many :video_markers, through: :taggings, source: :taggable, source_type: "VideoMarker"
  has_many :primary_video_markers, class_name: "VideoMarker", foreign_key: :primary_tag_id

  scoped_search on: [:name]
end
