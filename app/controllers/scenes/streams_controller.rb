class Scenes::StreamsController < ApplicationController
  include ActionController::Live

  before_action :set_scene

  # Byte-range streaming — works for native MP4/WebM and pre-generated transcodes
  def stream
    Rails.logger.debug "Range header: #{request.headers["Range"]}"
    send_file @scene.stream_file_path, disposition: "inline"
  end

  # Live remux — FFmpeg pipe, fragmented MP4, seeking via ?start=
  def stream_live
    start_time = params[:start].to_f

    cmd = %w[ffmpeg -hide_banner -loglevel error]
    cmd += ["-ss", start_time.to_s] if start_time > 0
    cmd += ["-i", @scene.path, "-c", "copy",
      "-movflags", "frag_keyframe+empty_moov",
      "-f", "mp4", "pipe:1"]

    response.headers["Content-Type"] = "video/mp4"
    response.headers["Cache-Control"] = "no-store"
    response.headers["Accept-Ranges"] = "none"

    IO.popen(cmd) do |ffmpeg|
      until ffmpeg.eof?
        response.stream.write(ffmpeg.read(16_384))
      end
    end
  rescue ActionController::Live::ClientDisconnected, Errno::EPIPE
    # client disconnected; IO.popen block exit sends SIGPIPE to ffmpeg
  ensure
    response.stream.close
  end

  private

  def set_scene
    @scene = Scene.find(params[:id])
  end
end
