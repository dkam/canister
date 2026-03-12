class VideosController < ApplicationController
  before_action :set_video, only: [:show, :update, :screenshot, :preview, :webp, :vtt, :chapter_vtt, :sprite, :sprite_vtt]

  # GET /videos
  def index
    @videos = Video.filter(video_filter_params) if video_filter_params.any?
    @videos ||= Video.all
    @videos = @videos.full_search(params[:q]) if params[:q].present?
    @videos = @videos.includes(:studio, :people)
    @videos = apply_sort(@videos)

    @pagy, @videos = pagy(@videos)

    @filters_active = video_filter_params.any? || params[:q].present? || params[:sort].present?
    @studios = Studio.order(:name)
    @people = Person.order(:name)
    @tags = Tag.order(:name)
  end

  # GET /videos/:id
  def show
    @markers = @video.video_markers.includes(:primary_tag)
    @stream_endpoints = build_stream_endpoints(@video)
  end

  # PATCH /videos/:id
  def update
    person_ids = params[:video].delete(:person_ids) if params[:video]&.key?(:person_ids)
    tag_ids = params[:video].delete(:tag_ids) if params[:video]&.key?(:tag_ids)

    scalar_params = params[:video]&.keys&.intersect?(%w[title details date rating])
    updated = scalar_params ? @video.update(video_update_params) : true

    if updated
      @video.person_ids = person_ids.map(&:to_s) if person_ids
      @video.tag_ids = tag_ids.map(&:to_s) if tag_ids
      render json: {
        success: true,
        date_display: @video.date&.strftime("%b %-d, %Y"),
        rating: @video.rating
      }
    else
      render json: { success: false, errors: @video.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def screenshot
    expires_in 1.week

    if params[:seconds]
      data = @video.screenshot(seconds: params[:seconds], width: params[:width])
      send_data data, filename: "screenshot.jpg", disposition: "inline", type: "image/jpeg"
      return
    end

    screenshot = @video.screenshots.first
    unless screenshot&.image&.attached?
      return send_file Rails.root.join("app/assets/images/no_thumbnail.svg"),
        disposition: "inline", type: "image/svg+xml"
    end

    send_data screenshot.image.download, filename: "screenshot.jpg", disposition: "inline", type: "image/jpeg"
  end

  def preview
    return head :not_found unless @video.preview_clip.attached?

    send_data @video.preview_clip.download, disposition: "inline", type: "video/mp4"
  end

  def webp
    screenshot
  end

  def vtt
    head :not_found
  end

  def chapter_vtt
    send_data @video.chapter_vtt, disposition: "inline"
  end

  def sprite
    return head :not_found unless @video.sprite_image.attached?

    expires_in 1.week
    send_data @video.sprite_image.download, disposition: "inline", type: "image/jpeg"
  end

  def sprite_vtt
    return head :not_found unless @video.sprite_vtt.attached?

    expires_in 1.week
    send_data @video.sprite_vtt.download, disposition: "inline", type: "text/vtt"
  end

  private

  def set_video
    # Try to find by UUID first
    @video = Video.find_by(id: params[:id])
    # If not found by UUID, try finding by any checksum
    @video ||= Checksum.find_by(hash_value: params[:id], hashable_type: "Video")&.hashable

    raise ActiveRecord::RecordNotFound unless @video
  end

  def build_stream_endpoints(video)
    url_for_kind = {
      direct: stream_video_path(video),
      hls: stream_hls_video_path(video),
      progressive: stream_mp4_video_path(video)
    }

    video.available_streams.map do |s|
      s.except(:kind).merge(
        url: url_for_kind.fetch(s[:kind]),
        seek_mode: s[:seek_mode].to_s,
        video_copy: s[:video_copy],
        audio_transcode: s[:audio_transcode]
      )
    end
  end

  def video_update_params
    params.require(:video).permit(:title, :details, :date, :rating)
  end

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

  def video_filter_params
    params.permit(:rating, :resolution, :studio_id, :has_markers, :q, :sort, :direction,
      tags: [], filter_people: [])
      .to_h
      .reject { |k, v| %w[q sort direction].include?(k) || v.blank? }
  end
end
