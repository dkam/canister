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

  # HLS manifest — three-tier resolution:
  #   1. Stored timestamps (remux only) — serve immediately, restart FFmpeg only if segments gone
  #   2. FFmpeg manifest on disk — reuse live/completed manifest
  #   3. Fresh start — calculated fallback while FFmpeg runs
  def stream_hls
    stream_config = @scene.available_streams.find { |s| s[:kind] == :hls }
    return head :not_found unless stream_config

    tmp_dir = hls_tmp_dir
    ffmpeg_manifest = tmp_dir.join("manifest.m3u8")

    Canister::StreamManager.instance.ensure_ffmpeg_running(@scene, stream_config)

    manifest = if @scene.hls_segment_durations.present? && stream_config[:video_copy]
      build_manifest_from_durations(@scene.hls_segment_durations)
    else
      generate_m3u8
    end

    render plain: manifest, content_type: "application/vnd.apple.mpegurl"
  end

  # HLS segment — delegates to StreamManager for FFmpeg lifecycle
  def stream_hls_segment
    segment = params[:segment].to_i
    config = @scene.available_streams.find { |s| s[:kind] == :hls }
    return head :not_found unless config

    result = Canister::StreamManager.instance.request_segment(@scene, segment, config)
    if result == :ok
      send_file hls_tmp_dir.join("#{segment}.ts"), disposition: "inline", type: "video/MP2T"
    else
      head :not_found
    end
  end

  private

  def hls_tmp_dir
    Rails.root.join("tmp", "hls", @scene.id.to_s)
  end

  def set_scene
    @scene = Scene.find(params[:id])
  end

  # Parse FFmpeg's manifest and substitute segment filenames with our URL helpers.
  # Handles both bare filenames ("42.ts") and dotfile names (".42.ts").
  def rewrite_ffmpeg_manifest(ffmpeg_manifest)
    lines = File.readlines(ffmpeg_manifest, chomp: true).map do |line|
      if (m = line.match(/\A\.?(\d+)\.ts\z/))
        stream_hls_segment_scene_url(@scene, segment: m[1].to_i)
      else
        line
      end
    end
    lines.join("\n")
  end

  # Calculated fallback manifest — used on fresh start before FFmpeg's manifest exists
  def generate_m3u8
    duration = @scene.duration.to_f
    segment_count = (duration / Canister::StreamManager::SEGMENT_DURATION).ceil
    last_duration = duration - ((segment_count - 1) * Canister::StreamManager::SEGMENT_DURATION)

    lines = [
      "#EXTM3U",
      "#EXT-X-VERSION:3",
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-TARGETDURATION:#{Canister::StreamManager::SEGMENT_DURATION}",
      "#EXT-X-PLAYLIST-TYPE:VOD"
    ]

    (0...segment_count).each do |i|
      seg_duration = (i == segment_count - 1) ? last_duration : Canister::StreamManager::SEGMENT_DURATION.to_f
      lines << "#EXTINF:#{format("%.3f", seg_duration)},"
      lines << stream_hls_segment_scene_url(@scene, segment: i)
    end

    lines << "#EXT-X-ENDLIST"
    lines.join("\n")
  end

  # Build manifest from previously stored #EXTINF durations (remux streams only).
  def build_manifest_from_durations(durations)
    lines = [
      "#EXTM3U",
      "#EXT-X-VERSION:3",
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-TARGETDURATION:#{durations.max.ceil}",
      "#EXT-X-PLAYLIST-TYPE:VOD"
    ]

    durations.each_with_index do |d, i|
      lines << "#EXTINF:#{format("%.3f", d)},"
      lines << stream_hls_segment_scene_url(@scene, segment: i)
    end

    lines << "#EXT-X-ENDLIST"
    lines.join("\n")
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
