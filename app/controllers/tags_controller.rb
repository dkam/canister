class TagsController < ApplicationController
  # GET /tags
  def index
    @tags = Tag.joins("LEFT JOIN taggings ON taggings.tag_id = tags.id AND taggings.taggable_type = 'Scene'")
               .select("tags.*, COUNT(taggings.id) AS scenes_count")
               .group("tags.id")
               .order("name ASC")
  end
end
