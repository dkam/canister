class Scenes::StreamsController < ApplicationController
  include ActionController::Live

  before_action :set_scene

  # Byte-range streaming — works for native MP4/WebM and pre-generated transcodes
  def stream
    return head :not_found if @scene.remote?
    Rails.logger.debug "Range header: #{request.headers["Range"]}"
    send_file @scene.stream_file_path, disposition: "inline"
  end

  # Progressive MP4 streaming — FFmpeg pipe, fragmented MP4, smart codec selection
  def stream_mp4
    stream_config = @scene.available_streams.find { |s| s[:kind] == :progressive && s[:mime_type] == "video/mp4" }

    return head :not_found unless stream_config

    start_time = params[:start].to_f

    Rails.logger.info "Streaming scene #{@scene.id} as MP4 (video_copy: #{stream_config[:video_copy]}, audio_transcode: #{stream_config[:audio_transcode]}, start: #{start_time})"

    cmd = build_ffmpeg_command(stream_config, start_time)

    Rails.logger.info "FFmpeg command: #{cmd.join(" ")}"

    response.headers["Content-Type"] = "video/mp4"
    response.headers["Cache-Control"] = "no-store"

    # Chrome sends Range requests for video and requires 206 to start playing.
    # For a pipe we don't know the output size, so fake it with a large number.
    # The stream will end naturally via chunked encoding terminator.
    if request.headers["Range"]&.start_with?("bytes=0")
      response.status = 206
      response.headers["Content-Range"] = "bytes 0-999999999/1000000000"
    end

    Open3.popen3(*cmd) do |stdin, stdout, stderr, wait_thr|
      bytes_written = 0

      # Consume stderr in background thread to prevent deadlock
      Thread.new do
        stderr_output = stderr.read
        Rails.logger.info "FFmpeg stderr: #{stderr_output}" if stderr_output.present?
      rescue IOError
      end

      # Stream to browser
      until stdout.eof?
        chunk = stdout.readpartial(16_384)
        bytes_written += chunk.length
        response.stream.write(chunk)
      end

      Rails.logger.info "Total bytes written: #{bytes_written}"
    end
  rescue ActionController::Live::ClientDisconnected, Errno::EPIPE
    Rails.logger.debug "Client disconnected during MP4 stream for scene #{@scene.id}"
  rescue => e
    Rails.logger.error "Error during MP4 stream for scene #{@scene.id}: #{e.class} - #{e.message}"
    raise e
  ensure
    response.stream.close
  end

  # HLS manifest — estimated uniform segments, process starts on first segment request
  def stream_hls
    stream_config = @scene.available_streams.find { |s| s[:kind] == :hls }
    return head :not_found unless stream_config

    manifest = Hls::ManifestBuilder.resolve(@scene, stream_config) do |segment_idx|
      stream_hls_segment_scene_url(@scene, segment: segment_idx)
    end

    render plain: manifest, content_type: "application/vnd.apple.mpegurl"
  end

  # HLS segment — delegates to StreamManager for FFmpeg lifecycle
  def stream_hls_segment
    segment = params[:segment].to_i
    config = @scene.available_streams.find { |s| s[:kind] == :hls }
    return head :not_found unless config

    result = Hls::StreamManager.instance.request_segment(@scene, segment, config)
    if result == :ok
      send_file Hls::StreamManager.instance.cache.hls_dir(@scene.id).join("#{segment}.ts"),
        disposition: "inline", type: "video/MP2T"
    else
      head :not_found
    end
  end

  private

  def set_scene
    @scene = Scene.find(params[:id])
  end

  def build_ffmpeg_command(config, start_time)
    cmd = %w[ffmpeg -hide_banner -loglevel error]

    cmd += ["-ss", start_time.to_s] if start_time > 0
    cmd += ["-i", @scene.ffmpeg_input]

    # Video codec
    cmd += if config[:video_copy]
      %w[-c:v copy]
    else
      %w[-c:v libx264 -preset veryfast -crf 23]
    end

    # Audio codec
    cmd += if config[:audio_transcode]
      %w[-c:a aac -ac 2]
    else
      # Copy audio (AAC or MP3)
      %w[-c:a copy]
    end

    # Output format
    cmd += %w[-movflags frag_keyframe+empty_moov -f mp4 pipe:1]

    cmd
  end
end
