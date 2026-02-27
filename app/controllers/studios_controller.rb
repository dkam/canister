class StudiosController < ApplicationController
  before_action :set_studio, only: [:show, :image]

  # GET /studios
  def index
    @studios = Studio.all
    @studios = @studios.search_for(params[:q]) if params[:q].present?
    @pagy, @studios = pagy(@studios)
  end

  # GET /studios/:id
  def show
    @pagy, @scenes = pagy(@studio.scenes.includes(:performers), limit: 24)
  end

  def image
    if stale?(@studio)
      type = detect_mime(@studio.image)
      expires_in 1.week
      response.headers['Content-Length'] = @studio.image.bytesize.to_s
      send_data @studio.image, disposition: 'inline', type: type
    end
  end

  private

    def set_studio
      @studio = Studio.find(params[:id])
    end

    def detect_mime(data)
      return "image/jpeg" unless data
      if data[0, 4] == "\x89PNG".b
        "image/png"
      elsif data[0, 2] == "\xFF\xD8".b
        "image/jpeg"
      else
        "image/jpeg"
      end
    end
end
