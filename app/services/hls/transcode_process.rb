module Hls
  class TranscodeProcess
    TranscodeStream = Struct.new(
      :video_id, :pid, :start_segment, :highest_generated,
      :output_dir, :config, :ffmpeg_input, :video_duration,
      :last_access, :last_requested_segment,
      keyword_init: true
    )

    attr_reader :stream

    def initialize
      @stream = nil
    end

    def start(video, config, from_segment, cache)
      stop if @stream&.pid

      output_dir = cache.ensure_dir(video.id)

      # Clean old segments and manifests when restarting
      cleanup_segments(output_dir) if from_segment > 0

      cmd = FfmpegCommand.build(
        input: video.ffmpeg_input,
        output_dir: output_dir,
        config: config,
        from_segment: from_segment
      )

      Rails.logger.info "HLS Transcode: starting for video #{video.id} from segment #{from_segment}"
      Rails.logger.info "HLS Transcode: #{cmd.join(" ")}"

      log_path = output_dir.join("ffmpeg.log")
      pid = Process.spawn(*cmd, out: "/dev/null", err: log_path.to_s)
      Process.detach(pid)

      @stream = TranscodeStream.new(
        video_id: video.id,
        pid: pid,
        start_segment: from_segment,
        highest_generated: from_segment - 1,
        output_dir: output_dir,
        config: config,
        ffmpeg_input: video.ffmpeg_input,
        video_duration: video.duration.to_f,
        last_access: Time.now,
        last_requested_segment: from_segment
      )
    end

    def stop
      return unless @stream&.pid
      kill_process(@stream.pid)
      @stream.pid = nil
    end

    def running?
      @stream&.pid && process_alive?(@stream.pid)
    end

    def video_id
      @stream&.video_id
    end

    def highest_generated
      @stream&.highest_generated || -1
    end

    def touch(segment_idx = nil)
      return unless @stream
      @stream.last_access = Time.now
      @stream.last_requested_segment = segment_idx if segment_idx
    end

    def last_requested_segment
      @stream&.last_requested_segment || 0
    end

    def idle_seconds
      return 0 unless @stream
      Time.now - @stream.last_access
    end

    # Called every monitor tick. Renames dotfiles, detects exit, saves durations.
    # Returns true if any segments were renamed (caller should broadcast CV).
    def monitor_tick
      return false unless @stream&.pid

      renamed_any = rename_dotfiles

      unless process_alive?(@stream.pid)
        Rails.logger.info "HLS Transcode: FFmpeg exited for video #{@stream.video_id}"
        rename_dotfiles(ffmpeg_exited: true)
        save_durations_from_manifest
        cleanup_transcode_manifest
        @stream.pid = nil
        return true
      end

      save_durations_from_manifest if renamed_any
      renamed_any
    end

    private

    def rename_dotfiles(ffmpeg_exited: false)
      return false unless @stream

      renamed_any = false
      dotfiles = Dir[@stream.output_dir.join(".*.ts")].sort_by { |f|
        File.basename(f)[/\.(\d+)\.ts/, 1].to_i
      }

      # A dotfile segment N is complete when dotfile N+1 exists (FFmpeg has moved on)
      dotfiles.each_cons(2) do |current, _next_file|
        n = File.basename(current)[/\.(\d+)\.ts/, 1]&.to_i
        next unless n

        dest = @stream.output_dir.join("#{n}.ts")
        begin
          File.rename(current, dest.to_s)
          @stream.highest_generated = [@stream.highest_generated, n].max
          renamed_any = true
        rescue Errno::ENOENT
          # Already renamed
        end
      end

      # Rename last dotfile if FFmpeg has exited
      if ffmpeg_exited && dotfiles.any?
        last = dotfiles.last
        n = File.basename(last)[/\.(\d+)\.ts/, 1]&.to_i
        if n
          dest = @stream.output_dir.join("#{n}.ts")
          begin
            File.rename(last, dest.to_s)
            @stream.highest_generated = [@stream.highest_generated, n].max
            renamed_any = true
          rescue Errno::ENOENT; end
        end
      end

      renamed_any
    end

    # Parse manifest and save segment durations to DB.
    def save_durations_from_manifest
      return unless @stream
      manifest_path = @stream.output_dir.join("manifest.m3u8")
      return unless manifest_path.exist?

      content = manifest_path.read
      parsed = {}
      current_segment = @stream.start_segment

      content.each_line do |line|
        if (m = line.match(/#EXTINF:([\d.]+),/))
          parsed[current_segment] = m[1].to_f
          current_segment += 1
        end
      end

      return if parsed.empty?

      video = Video.find_by(id: @stream.video_id)
      return unless video

      existing = video.hls_segment_durations || {}
      existing = {} unless existing.is_a?(Hash)
      merged = existing.merge(parsed.transform_keys(&:to_s))

      if merged != existing
        video.update_column(:hls_segment_durations, merged)
        Rails.logger.debug "HLS Transcode: saved #{merged.size} durations for video #{@stream.video_id}"
      end
    rescue ActiveRecord::RecordNotFound
      # Video deleted
    end

    # Remove the throwaway manifest that FFmpeg writes.
    def cleanup_transcode_manifest
      return unless @stream
      manifest = @stream.output_dir.join("manifest.m3u8")
      File.delete(manifest.to_s) rescue nil
    end

    def cleanup_segments(output_dir)
      Dir[output_dir.join(".*.ts")].each { |f| File.delete(f) rescue nil }
      manifest = output_dir.join("manifest.m3u8")
      File.delete(manifest.to_s) rescue nil
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end

    def kill_process(pid)
      Process.kill("TERM", pid)
      Thread.new do
        sleep 5
        Process.kill("KILL", pid) rescue nil
      end
    rescue Errno::ESRCH
      # Already exited
    end
  end
end
