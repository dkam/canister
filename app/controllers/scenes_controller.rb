class ScenesController < ApplicationController
  before_action :set_scene, only: [:show, :update, :screenshot, :preview, :webp, :vtt, :chapter_vtt]

  # GET /scenes
  def index
    @scenes = Scene.filter(scene_filter_params) if scene_filter_params.any?
    @scenes ||= Scene.all
    @scenes = @scenes.full_search(params[:q]) if params[:q].present?
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

  # PATCH /scenes/:id
  def update
    performer_ids = params[:scene].delete(:performer_ids) if params[:scene]&.key?(:performer_ids)
    tag_ids = params[:scene].delete(:tag_ids) if params[:scene]&.key?(:tag_ids)

    scalar_params = params[:scene]&.keys&.intersect?(%w[title details date rating])
    updated = scalar_params ? @scene.update(scene_update_params) : true

    if updated
      @scene.performer_ids = performer_ids.map(&:to_s) if performer_ids
      @scene.tag_ids = tag_ids.map(&:to_s) if tag_ids
      render json: {
        success: true,
        date_display: @scene.date&.strftime("%b %-d, %Y"),
        rating: @scene.rating
      }
    else
      render json: { success: false, errors: @scene.errors.full_messages }, status: :unprocessable_entity
    end
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

  def scene_update_params
    params.require(:scene).permit(:title, :details, :date, :rating)
  end

  def scene_filter_params
    params.permit(:rating, :resolution, :studio_id, :has_markers, :q, :sort, :direction,
      tags: [], filter_performers: [])
      .to_h
      .reject { |k, v| %w[q sort direction].include?(k) || v.blank? }
  end
end
