class PeopleController < ApplicationController
  before_action :set_person, only: [:show, :image]

  # GET /people
  def index
    @people = Performer.all
    @people = @people.search_for(params[:q]) if params[:q].present?
    @people = @people.filter_favorites(params[:favorites] == "true") if params[:favorites].present?
    @pagy, @people = pagy(@people, limit: 48)
  end

  # GET /people/:id
  def show
    @pagy, @scenes = pagy(@person.scenes.includes(:studio))
  end

  def image
    if stale?(@person)
      type = detect_mime(@person.image)
      expires_in 1.week
      response.headers['Content-Length'] = @person.image.bytesize.to_s
      send_data @person.image, disposition: 'inline', type: type
    end
  end

  private

    def set_person
      @person = Performer.find(params[:id])
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
