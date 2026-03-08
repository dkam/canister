class VideoMarkersController < ApplicationController
  before_action :set_video_marker, only: [:stream, :preview]

  # GET /videos/:video_id/video_markers/:id/stream
  def stream
    send_file @video_marker.stream_file_path, disposition: 'inline'
  end

  # GET /videos/:video_id/video_markers/:id/preview
  def preview
    send_file @video_marker.stream_preview_path, disposition: 'inline'
  end

  private

    def set_video_marker
      @video_marker = VideoMarker.find(params[:id])
    end
end
