class StudiosController < ApplicationController
  before_action :set_studio, only: [:show, :image]

  # GET /studios
  def index
    @studios = Studio.order(:name)
    @studios = @studios.search_for(params[:q]) if params[:q].present?
    @pagy, @studios = pagy(@studios)
  end

  # GET /studios/:id
  def show
    @pagy, @videos = pagy(@studio.videos.includes(:people), limit: 24)
  end

  def image
    return head :not_found unless @studio.image.attached?

    if stale?(@studio.image)
      expires_in 1.week
      redirect_to @studio.image
    end
  end

  private

  def set_studio
    @studio = Studio.find(params[:id])
  end
end
