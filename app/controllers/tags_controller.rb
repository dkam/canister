class TagsController < ApplicationController
  # GET /tags
  def index
    @tags = Tag.joins("LEFT JOIN taggings ON taggings.tag_id = tags.id AND taggings.taggable_type = 'Scene'")
               .select("tags.*, COUNT(taggings.id) AS scenes_count")
               .group("tags.id")
               .order("name ASC")
  end

  # POST /tags
  def create
    tag = Tag.where(name: params[:name].strip).first_or_create!
    render json: { id: tag.id, name: tag.name }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # GET /tags/search.json?q=term
  def search
    tags = Tag.order(:name)
    tags = tags.search_for(params[:q]) if params[:q].present?
    render json: tags.limit(20).map { |t| { id: t.id, name: t.name } }
  end
end
