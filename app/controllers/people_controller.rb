class PeopleController < ApplicationController
  before_action :set_person, only: [:show, :image]

  # GET /people
  def index
    @people = Person.order(:name)
    @people = @people.search_for(params[:q]) if params[:q].present?
    @people = @people.filter_favorites(params[:favorites] == "true") if params[:favorites].present?
    @pagy, @people = pagy(@people, limit: 48)
  end

  # GET /people/:id
  def show
    @pagy, @videos = pagy(@person.videos.includes(:studio))
  end

  # GET /people/search.json?q=term
  def search
    people = Person.order(:name)
    people = people.search_for(params[:q]) if params[:q].present?
    render json: people.limit(20).map { |p| { id: p.id, name: p.name } }
  end

  # POST /people
  def create
    person = Person.new(name: params[:name])
    person.skip_image_validation = true
    if person.save
      render json: { id: person.id, name: person.name }, status: :created
    else
      render json: { errors: person.errors.full_messages }, status: :unprocessable_entity
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
    @person = Person.find(params[:id])
  end
end
