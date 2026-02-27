class PerformersController < ApplicationController
  before_action :set_performer, only: [:show, :image]

  # GET /performers
  def index
    @performers = Performer.all
    @performers = @performers.search_for(params[:q]) if params[:q].present?
    @performers = @performers.filter_favorites(params[:favorites] == "true") if params[:favorites].present?
    @pagy, @performers = pagy(@performers, limit: 48)
  end

  # GET /performers/:id
  def show
    @pagy, @scenes = pagy(@performer.scenes.includes(:studio))
  end

  def image
    if stale?(@performer)
      type = detect_mime(@performer.image)
      expires_in 1.week
      response.headers['Content-Length'] = @performer.image.bytesize.to_s
      send_data @performer.image, disposition: 'inline', type: type
    end
  end

  private

    def set_performer
      @performer = Performer.find(params[:id])
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
