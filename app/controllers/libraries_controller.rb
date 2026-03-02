class LibrariesController < ApplicationController
  before_action :set_library, only: [:show, :edit, :update, :destroy, :scan]

  def index
    @libraries = Library.order(:name)
    @pagy, @libraries = pagy(@libraries)
  end

  def show
    @pagy, @scenes = pagy(@library.scenes.includes(:performers, :studio), limit: 24)
  end

  def new
    @library = Library.new
  end

  def create
    @library = Library.new(library_params)
    if @library.save
      redirect_to @library, notice: "Library created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @library.update(library_params)
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

  private

  def set_library
    @library = Library.find(params[:id])
  end

  def library_params
    permitted = params.require(:library).permit(:name, :path, :kind, :read_only, :default_video_kind, :username, :password)
    permitted.delete(:password) if permitted[:password].blank?
    permitted
  end
end
