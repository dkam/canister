class ScenesController < ApplicationController
  before_action :set_scene, only: [:show, :screenshot, :preview, :webp, :vtt, :chapter_vtt]

  # GET /scenes
  def index
    @scenes = Scene.filter(scene_filter_params) if scene_filter_params.any?
    @scenes ||= Scene.all
    @scenes = @scenes.includes(:studio, :performers).order(created_at: :desc)

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
    @stream_endpoints = build_stream_endpoints(@scene)
  end

  def screenshot
    expires_in 1.week

    if params[:seconds]
      data = @scene.screenshot(seconds: params[:seconds], width: params[:width])
      send_data data, filename: "screenshot.jpg", disposition: "inline", type: "image/jpeg"
      return
    end

    screenshot = @scene.screenshots.first
    return head :not_found unless screenshot&.image&.attached?

    send_data screenshot.image.download, filename: "screenshot.jpg", disposition: "inline", type: "image/jpeg"
  end

  def preview
    return head :not_found unless @scene.preview_clip.attached?

    send_data @scene.preview_clip.download, disposition: "inline", type: "video/mp4"
  end

  def webp
    screenshot
  end

  def vtt
    head :not_found
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

    # Try to find by UUID first
    @scene = Scene.find_by(id: params[:id])
    # If not found by UUID, try finding by any checksum
    @scene ||= Checksum.find_by(hash_value: params[:id], hashable_type: "Scene")&.hashable

    raise ActiveRecord::RecordNotFound unless @scene
  end

  def build_stream_endpoints(scene)
    url_for_kind = {
      direct: stream_scene_path(scene),
      hls: stream_hls_scene_path(scene),
      progressive: stream_mp4_scene_path(scene)
    }

    scene.available_streams.map do |s|
      s.except(:kind).merge(
        url: url_for_kind.fetch(s[:kind]),
        seek_mode: s[:seek_mode].to_s,
        video_copy: s[:video_copy],
        audio_transcode: s[:audio_transcode]
      )
    end
  end

  def scene_filter_params
    params.permit(:rating, :resolution, :studio_id, :has_markers,
      tags: [], filter_performers: [])
      .to_h
      .reject { |_, v| v.blank? }
  end
end
