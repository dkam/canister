class LibrariesController < ApplicationController
  before_action :set_library, only: [:show, :edit, :update, :destroy, :scan]

  def index
    @libraries = Library.order(:name)
    @pagy, @libraries = pagy(@libraries)
  end

  def show
    videos = @library.videos.includes(:people, :studio)
    videos = apply_sort(videos)
    @pagy, @videos = pagy(videos, limit: 24)
  end

  def new
    @library = Library.new
  end

  def create
    @library = Library.new(library_params)
    auto_detect_kind(@library)
    if @library.save
      @library.scan
      redirect_to @library, notice: "Library created. Scan queued."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @library.assign_attributes(library_params)
    auto_detect_kind(@library)
    if @library.save
      redirect_to @library, notice: "Library updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @library.destroy
    redirect_to libraries_path, notice: "Library deleted."
  end

  def scan
    @library.scan
    redirect_to @library, notice: "Scan queued for #{@library.name}."
  end

  def detect_kind
    detector = Library::KindDetector.new(
      params[:path],
      username: params[:username],
      password: params[:password]
    )
    render json: { kind: detector.detect }
  end

  private

  def apply_sort(scope)
    sort = params[:sort].presence || "created_at"
    direction = params[:direction] == "asc" ? "asc" : "desc"

    case sort
    when "random"
      scope.reorder(Arel.sql("RANDOM()"))
    when "size"
      scope.reorder(Arel.sql("CAST(videos.size AS INTEGER) #{direction}"))
    when *%w[created_at title date rating duration path]
      scope.reorder("videos.#{sort} #{direction}")
    else
      scope.reorder("videos.created_at #{direction}")
    end
  end

  def set_library
    @library = Library.find(params[:id])
  end

  def library_params
    permitted = params.require(:library).permit(:name, :path, :kind, :read_only, :default_video_kind, :username, :password)
    permitted.delete(:password) if permitted[:password].blank?
    permitted
  end

  def auto_detect_kind(library)
    return unless library.kind.blank? || library.kind == "auto"
    return if library.path.blank?

    library.kind = Library::KindDetector.new(
      library.path,
      username: library.username,
      password: library.password
    ).detect
  end
end
