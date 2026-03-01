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

  # HLS manifest — reuses existing segments/manifest if present, otherwise starts FFmpeg
  def stream_hls
    stream_config = @scene.available_streams.find { |s| s[:kind] == :hls }
    return head :not_found unless stream_config

    tmp_dir = hls_tmp_dir
    ffmpeg_manifest = tmp_dir.join("manifest.m3u8")

    if ffmpeg_manifest.exist?
      # Segments exist from a previous (or current) FFmpeg run — reuse them.
      # If FFmpeg is still running it will keep adding segments; if done, they're all there.
      manifest = rewrite_ffmpeg_manifest(ffmpeg_manifest)
    else
      # Fresh start — no rm_rf, just mkdir_p
      FileUtils.mkdir_p(tmp_dir)
      start_hls_ffmpeg(stream_config, tmp_dir)
      manifest = generate_m3u8  # calculated fallback while FFmpeg runs
    end

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
  HLS_RUNNING = Mutex.new
  HLS_PIDS    = Set.new         # scene IDs currently being transcoded

  def hls_tmp_dir
    Rails.root.join("tmp", "hls", @scene.id.to_s)
  end

  def set_scene
    @scene = Scene.find(params[:id])
  end

  def start_hls_ffmpeg(config, tmp_dir)
    HLS_RUNNING.synchronize do
      return if HLS_PIDS.include?(@scene.id)
      HLS_PIDS.add(@scene.id)
    end

    cmd = build_hls_ffmpeg_command(config, tmp_dir)
    Rails.logger.info "HLS FFmpeg: #{cmd.join(" ")}"

    Thread.new do
      done = false

      # Watcher: renames .N.ts → N.ts once segment N is complete.
      # Segment N is complete when .(N+1).ts has appeared (FFmpeg has moved on).
      watcher = Thread.new do
        renamed = Set.new
        until done
          Dir[tmp_dir.join(".*.ts")].sort.each_cons(2) do |a, _b|
            n = File.basename(a)[/\.(\d+)\.ts/, 1]&.to_i
            next unless n && !renamed.include?(n)
            File.rename(a, tmp_dir.join("#{n}.ts"))
            renamed.add(n)
          end
          sleep 0.2
        end
        # After FFmpeg exits, rename any remaining dotfiles
        Dir[tmp_dir.join(".*.ts")].each do |f|
          n = File.basename(f)[/\.(\d+)\.ts/, 1]
          File.rename(f, tmp_dir.join("#{n}.ts")) if n
        end
      end

      Open3.popen3(*cmd) do |_stdin, _stdout, stderr, wait_thr|
        err = stderr.read
        Rails.logger.info "HLS FFmpeg stderr: #{err}" if err.present?
        wait_thr.value
      end
    rescue => e
      Rails.logger.error "HLS FFmpeg error scene #{@scene.id}: #{e.message}"
    ensure
      done = true
      watcher&.join
      HLS_RUNNING.synchronize { HLS_PIDS.delete(@scene.id) }
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
      "-hls_segment_filename", tmp_dir.join(".%d.ts").to_s,
      tmp_dir.join("manifest.m3u8").to_s
    ]

    cmd
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
