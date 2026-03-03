class PeopleController < ApplicationController
  before_action :set_person, only: [:show, :image]

  # GET /people
  def index
    @people = Performer.order(:name)
    @people = @people.search_for(params[:q]) if params[:q].present?
    @people = @people.filter_favorites(params[:favorites] == "true") if params[:favorites].present?
    @pagy, @people = pagy(@people, limit: 48)
  end

  # GET /people/:id
  def show
    @pagy, @scenes = pagy(@person.scenes.includes(:studio))
  end

  # GET /people/search.json?q=term
  def search
    people = Performer.order(:name)
    people = people.search_for(params[:q]) if params[:q].present?
    render json: people.limit(20).map { |p| { id: p.id, name: p.name } }
  end

  # POST /people
  def create
    performer = Performer.new(name: params[:name])
    performer.skip_image_validation = true
    if performer.save
      render json: { id: performer.id, name: performer.name }, status: :created
    else
      render json: { errors: performer.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def image
    return head :not_found unless @person.image.attached?
    
    if stale?(@person.image)
      expires_in 1.week
      redirect_to @person.image
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
