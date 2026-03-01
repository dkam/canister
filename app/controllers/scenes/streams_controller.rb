class Scenes::StreamsController < ApplicationController
  include ActionController::Live

  before_action :set_scene

  # Byte-range streaming — works for native MP4/WebM and pre-generated transcodes
  def stream
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

  # HLS manifest — starts FFmpeg segmenter, returns M3U8
  def stream_hls
    stream_config = @scene.available_streams.find { |s| s[:kind] == :hls }
    return head :not_found unless stream_config

    tmp_dir = hls_tmp_dir
    FileUtils.rm_rf(tmp_dir)
    FileUtils.mkdir_p(tmp_dir)

    start_hls_ffmpeg(stream_config, tmp_dir)

    manifest = generate_m3u8(tmp_dir)
    render plain: manifest, content_type: "application/vnd.apple.mpegurl"
  end

  # HLS segment — waits for .ts file, then serves it
  def stream_hls_segment
    segment = params[:segment].to_i
    segment_path = hls_tmp_dir.join("#{segment}.ts")

    deadline = Time.now + HLS_SEGMENT_WAIT_TIMEOUT
    loop do
      break if File.exist?(segment_path)
      return head :not_found if Time.now > deadline
      sleep 0.1
    end

    send_file segment_path, disposition: "inline", type: "video/MP2T"
  end

  private

  HLS_SEGMENT_DURATION = 2      # seconds
  HLS_SEGMENT_WAIT_TIMEOUT = 15 # seconds

  def hls_tmp_dir
    Rails.root.join("tmp", "hls", @scene.id.to_s)
  end

  def set_scene
    @scene = Scene.find(params[:id])
  end

  def start_hls_ffmpeg(config, tmp_dir)
    cmd = build_hls_ffmpeg_command(config, tmp_dir)
    Rails.logger.info "HLS FFmpeg command: #{cmd.join(" ")}"

    Thread.new do
      Open3.popen3(*cmd) do |_stdin, _stdout, stderr, wait_thr|
        err = stderr.read
        Rails.logger.info "HLS FFmpeg stderr: #{err}" if err.present?
        wait_thr.value
      end
    rescue => e
      Rails.logger.error "HLS FFmpeg error for scene #{@scene.id}: #{e.message}"
    end
  end

  def build_hls_ffmpeg_command(config, tmp_dir)
    cmd = %w[ffmpeg -hide_banner -loglevel error]
    cmd += ["-i", @scene.path]

    if config[:video_copy]
      cmd += %w[-c:v copy]
    else
      # Force keyframes at segment boundaries — only valid when transcoding, not with copy
      cmd += %w[-flags +cgop -force_key_frames expr:gte(t,n_forced*2)]
      cmd += %w[-c:v libx264 -preset veryfast -crf 23]
    end

    cmd += if config[:audio_transcode]
      %w[-c:a aac -ac 2]
    else
      %w[-c:a copy]
    end

    cmd += %w[-sn -copyts -avoid_negative_ts disabled]
    cmd += [
      "-f", "hls",
      "-start_number", "0",
      "-hls_time", HLS_SEGMENT_DURATION.to_s,
      "-hls_flags", "split_by_time",
      "-hls_segment_type", "mpegts",
      "-hls_playlist_type", "vod",
      "-hls_segment_filename", tmp_dir.join("%d.ts").to_s,
      tmp_dir.join("manifest.m3u8").to_s
    ]

    cmd
  end

  def generate_m3u8(tmp_dir)
    duration = @scene.duration.to_f
    segment_count = (duration / HLS_SEGMENT_DURATION).ceil
    last_duration = duration - ((segment_count - 1) * HLS_SEGMENT_DURATION)

    lines = [
      "#EXTM3U",
      "#EXT-X-VERSION:3",
      "#EXT-X-MEDIA-SEQUENCE:0",
      "#EXT-X-TARGETDURATION:#{HLS_SEGMENT_DURATION}",
      "#EXT-X-PLAYLIST-TYPE:VOD"
    ]

    (0...segment_count).each do |i|
      seg_duration = (i == segment_count - 1) ? last_duration : HLS_SEGMENT_DURATION.to_f
      lines << "#EXTINF:#{format("%.3f", seg_duration)},"
      lines << stream_hls_segment_scene_url(@scene, segment: i)
    end

    lines << "#EXT-X-ENDLIST"
    lines.join("\n")
  end

  def build_ffmpeg_command(config, start_time)
    cmd = %w[ffmpeg -hide_banner -loglevel error]

    cmd += ["-ss", start_time.to_s] if start_time > 0
    cmd += ["-i", @scene.path]

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
