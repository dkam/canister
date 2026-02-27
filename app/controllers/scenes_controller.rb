class ScenesController < ApplicationController
  before_action :set_scene, only: [:show, :stream, :screenshot, :preview, :webp, :vtt, :chapter_vtt]

  # GET /scenes
  def index
    @scenes = Scene.filter(scene_filter_params) if scene_filter_params.any?
    @scenes ||= Scene.all
    @scenes = @scenes.includes(:studio, :performers)

    if params[:sort].present?
      allowed = %w[title date rating duration path]
      sort_col = allowed.include?(params[:sort]) ? params[:sort] : "path"
      direction = (params[:direction] == "desc") ? "desc" : "asc"
      @scenes = @scenes.reorder("scenes.#{sort_col} #{direction}")
    end

    @pagy, @scenes = pagy(@scenes)

    @filters_active = scene_filter_params.any? || params[:q].present? || params[:sort].present?
    @studios = Studio.order(:name)
    @performers = Performer.order(:name)
    @tags = Tag.order(:name)
  end

  # GET /scenes/:id
  def show
    @markers = @scene.scene_markers.includes(:primary_tag)
  end

  def stream
    send_file @scene.stream_file_path, disposition: "inline"
  end

  def screenshot
    path = File.join(Stash::STASH_SCREENSHOTS_DIRECTORY, "#{@scene.checksum}.jpg")
    thumb_path = File.join(Stash::STASH_SCREENSHOTS_DIRECTORY, "#{@scene.checksum}.thumb.jpg")

    expires_in 1.week

    if params[:seconds]
      data = @scene.screenshot(seconds: params[:seconds], width: params[:width])
      send_data data, filename: "screenshot.jpg", disposition: "inline"
    elsif File.exist?(thumb_path) && params[:width] && params[:width].to_i < 400
      response.headers["Content-Length"] = File.size(thumb_path).to_s
      send_file thumb_path, disposition: "inline"
    else
      response.headers["Content-Length"] = File.size(path).to_s
      send_file path, disposition: "inline"
    end
  end

  def preview
    path = File.join(Stash::STASH_SCREENSHOTS_DIRECTORY, "#{@scene.checksum}.mp4")
    if File.exist?(path)
      send_file path, disposition: "inline"
    else
      render json: {}, status: :not_found
    end
  end

  def webp
    path = File.join(Stash::STASH_SCREENSHOTS_DIRECTORY, "#{@scene.checksum}.webp")
    if File.exist?(path)
      send_file path, disposition: "inline"
    else
      screenshot
    end
  end

  def vtt
    path = if params[:format] == "jpg"
      File.join(Stash::STASH_VTT_DIRECTORY, "#{@scene.checksum}_sprite.jpg")
    else
      File.join(Stash::STASH_VTT_DIRECTORY, "#{@scene.checksum}_thumbs.vtt")
    end

    send_file path, disposition: "inline"
  end

  def chapter_vtt
    send_data @scene.chapter_vtt, disposition: "inline"
  end

  private

  def set_scene
    if params[:id].include?(".vtt")
      params[:id].slice!("_thumbs.vtt")
      params[:format] = "vtt"
    end
    if params[:id].include?(".jpg")
      params[:id].slice!("_sprite.jpg")
      params[:format] = "jpg"
    end

    @scene = Scene.find_by(checksum: params[:id]) || Scene.find(params[:id])
  end

  def scene_filter_params
    params.permit(:rating, :resolution, :studio_id, :has_markers,
      tags: [], filter_performers: [])
      .to_h
      .reject { |_, v| v.blank? }
  end
end
