require "singleton"
require "open3"

module Canister
  class StreamManager
    include Singleton

    SEGMENT_DURATION     = 2       # seconds per segment
    SEGMENT_WAIT_TIMEOUT = 15      # max seconds to wait for segment file
    MAX_SEGMENT_BUFFER   = 15      # kill FFmpeg when this many segments ahead of last_requested
    KEEP_FIRST_SEGMENTS  = 15      # always keep first N segments on disk for fast start
    MAX_SEGMENT_GAP      = 5       # restart if request > this many segments ahead of highest_generated
    MAX_IDLE_TIME        = 30      # kill after 30s no requests
    MONITOR_INTERVAL     = 0.2     # background check frequency (seconds)
    FFMPEG_TERM_WAIT     = 5       # seconds between SIGTERM and SIGKILL
    MAX_CACHE_SIZE       = (ENV.fetch("HLS_MAX_CACHE_SIZE_GB", "5").to_f * 1024 * 1024 * 1024).to_i

    RunningStream = Struct.new(
      :scene_id, :pid, :start_segment, :highest_generated,
      :last_requested, :last_accessed_at, :output_dir, :config, :scene_path,
      keyword_init: true
    )

    def initialize
      @mutex = Mutex.new
      @cv = ConditionVariable.new
      @streams = {}       # scene_id => RunningStream
      @cache_lru = {}     # scene_id => Time (Ruby Hash preserves insertion order)
      @monitor_thread = nil
      @shutting_down = false
      populate_cache_lru
    end

    # Called from stream_hls — ensures FFmpeg is running for the scene
    def ensure_ffmpeg_running(scene, config)
      @mutex.synchronize do
        touch_cache(scene.id)
        stream = @streams[scene.id]
        return if stream&.pid

        output_dir = hls_tmp_dir(scene.id)
        FileUtils.mkdir_p(output_dir)

        stream = RunningStream.new(
          scene_id: scene.id,
          pid: nil,
          start_segment: 0,
          highest_generated: -1,
          last_requested: 0,
          last_accessed_at: Time.now,
          output_dir: output_dir,
          config: config,
          scene_path: scene.path
        )
        @streams[scene.id] = stream
        start_ffmpeg(stream, 0)
        ensure_monitor_running
      end
    end

    # Called from stream_hls_segment — returns :ok or :not_found
    def request_segment(scene, segment_idx, config)
      segment_path = hls_tmp_dir(scene.id).join("#{segment_idx}.ts")

      # Fast path: segment already cached on disk
      return :ok if segment_path.exist?

      @mutex.synchronize do
        touch_cache(scene.id)
        stream = @streams[scene.id]

        if stream.nil? || stream.pid.nil?
          # No FFmpeg running — start one
          output_dir = hls_tmp_dir(scene.id)
          FileUtils.mkdir_p(output_dir)

          stream = RunningStream.new(
            scene_id: scene.id,
            pid: nil,
            start_segment: segment_idx,
            highest_generated: -1,
            last_requested: segment_idx,
            last_accessed_at: Time.now,
            output_dir: output_dir,
            config: config,
            scene_path: scene.path
          )
          @streams[scene.id] = stream
          start_ffmpeg(stream, segment_idx)
          ensure_monitor_running
        elsif needs_restart?(stream, segment_idx)
          # Seek too far ahead — kill and restart
          Rails.logger.info "HLS StreamManager: restarting FFmpeg for scene #{scene.id} at segment #{segment_idx} (was at #{stream.highest_generated})"
          stop_ffmpeg(stream)
          stream.start_segment = segment_idx
          stream.highest_generated = -1
          start_ffmpeg(stream, segment_idx)
        end

        # Update tracking
        stream.last_requested = [stream.last_requested, segment_idx].max
        stream.last_accessed_at = Time.now

        # Wait for segment to appear on disk
        deadline = Time.now + SEGMENT_WAIT_TIMEOUT
        until segment_path.exist? || @shutting_down
          remaining = deadline - Time.now
          break if remaining <= 0
          @cv.wait(@mutex, remaining)
        end
      end

      segment_path.exist? ? :ok : :not_found
    end

    # Kill all FFmpeg processes (called at exit)
    def shutdown
      @mutex.synchronize do
        @shutting_down = true
        @streams.each_value { |s| stop_ffmpeg(s) }
        @cv.broadcast
      end
      @monitor_thread&.join(10)
    end

    private

    def hls_tmp_dir(scene_id)
      Rails.root.join("tmp", "hls", scene_id.to_s)
    end

    def touch_cache(scene_id)
      @cache_lru.delete(scene_id)
      @cache_lru[scene_id] = Time.now
    end

    def populate_cache_lru
      hls_root = Rails.root.join("tmp", "hls")
      return unless hls_root.exist?

      dirs = Dir.children(hls_root)
        .map { |d| [d, hls_root.join(d)] }
        .select { |_, p| File.directory?(p) }
        .sort_by { |_, p| File.mtime(p) }

      dirs.each { |id, _| @cache_lru[id] = Time.now }
    end

    def needs_restart?(stream, segment_idx)
      return false if segment_idx <= stream.highest_generated
      return false if stream.highest_generated == -1  # just started, give it time

      gap = segment_idx - stream.highest_generated
      gap > MAX_SEGMENT_GAP
    end

    def start_ffmpeg(stream, from_segment)
      cmd = build_hls_ffmpeg_command(stream, from_segment)
      Rails.logger.info "HLS StreamManager: starting FFmpeg for scene #{stream.scene_id} at segment #{from_segment}"
      Rails.logger.info "HLS StreamManager: #{cmd.join(" ")}"

      # Remove old manifest when restarting mid-stream so the controller
      # falls through to the calculated manifest instead of serving a stale one
      manifest = stream.output_dir.join("manifest.m3u8")
      manifest.delete if from_segment > 0 && manifest.exist?

      log_path = stream.output_dir.join("ffmpeg.log")
      pid = Process.spawn(*cmd, out: "/dev/null", err: log_path.to_s)
      Process.detach(pid)
      stream.pid = pid
      stream.start_segment = from_segment
      stream.highest_generated = from_segment - 1
    end

    def stop_ffmpeg(stream)
      pid = stream.pid
      return unless pid

      stream.pid = nil

      Thread.new do
        begin
          Process.kill("TERM", pid)
          sleep FFMPEG_TERM_WAIT
          Process.kill("KILL", pid)
        rescue Errno::ESRCH
          # Process already exited
        end

        # Final dotfile rename after FFmpeg exits
        rename_dotfiles(stream)
        save_hls_timestamps(stream)
      end
    end

    def build_hls_ffmpeg_command(stream, from_segment)
      config = stream.config
      cmd = %w[ffmpeg -hide_banner -loglevel error]

      if from_segment > 0
        cmd += ["-ss", (from_segment * SEGMENT_DURATION).to_s]
      end

      cmd += ["-i", stream.scene_path]

      if config[:video_copy]
        cmd += %w[-c:v copy]
      else
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
        "-start_number", from_segment.to_s,
        "-hls_time", SEGMENT_DURATION.to_s,
        "-hls_flags", "split_by_time",
        "-hls_segment_type", "mpegts",
        "-hls_playlist_type", "vod",
        "-hls_segment_filename", stream.output_dir.join(".%d.ts").to_s,
        stream.output_dir.join("manifest.m3u8").to_s
      ]

      cmd
    end

    def ensure_monitor_running
      return if @monitor_thread&.alive?

      @monitor_thread = Thread.new do
        monitor_loop
      rescue => e
        Rails.logger.error "HLS StreamManager monitor error: #{e.class} - #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}"
      end
    end

    def monitor_loop
      until @shutting_down
        @mutex.synchronize do
          @streams.each_value do |stream|
            next unless stream.pid

            # Rename dotfiles and update highest_generated
            renamed_any = rename_dotfiles(stream)
            @cv.broadcast if renamed_any

            # Check if FFmpeg process has exited
            unless process_alive?(stream.pid)
              Rails.logger.info "HLS StreamManager: FFmpeg exited for scene #{stream.scene_id}"
              rename_dotfiles(stream)
              save_hls_timestamps(stream)
              stream.pid = nil
              @cv.broadcast
              next
            end

            # Buffer-full check: count consecutive segments from last_requested
            if buffer_full?(stream)
              Rails.logger.info "HLS StreamManager: buffer full for scene #{stream.scene_id}, killing FFmpeg"
              stop_ffmpeg(stream)
            end

            # Idle check
            if stream.last_accessed_at + MAX_IDLE_TIME < Time.now
              Rails.logger.info "HLS StreamManager: idle timeout for scene #{stream.scene_id}, killing FFmpeg"
              stop_ffmpeg(stream)
            end
          end
        end

        evict_cache_if_needed

        sleep MONITOR_INTERVAL
      end
    end

    def rename_dotfiles(stream)
      renamed_any = false
      dotfiles = Dir[stream.output_dir.join(".*.ts")].sort_by { |f|
        File.basename(f)[/\.(\d+)\.ts/, 1].to_i
      }

      # A dotfile segment N is complete when dotfile N+1 exists (FFmpeg has moved on)
      dotfiles.each_cons(2) do |current, _next_file|
        n = File.basename(current)[/\.(\d+)\.ts/, 1]&.to_i
        next unless n

        dest = stream.output_dir.join("#{n}.ts")
        next if dest.exist?

        begin
          File.rename(current, dest.to_s)
          stream.highest_generated = [stream.highest_generated, n].max
          renamed_any = true
        rescue Errno::ENOENT
          # File was already renamed or removed
        end
      end

      renamed_any
    end

    def buffer_full?(stream)
      count = 0
      seg = stream.last_requested
      loop do
        break unless stream.output_dir.join("#{seg}.ts").exist?
        count += 1
        seg += 1
      end
      count >= MAX_SEGMENT_BUFFER
    end

    def process_alive?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end

    def save_hls_timestamps(stream)
      return unless stream.config[:video_copy]
      # Only save timestamps from a full run (started at segment 0),
      # otherwise the manifest only contains partial durations from the restart point
      return unless stream.start_segment == 0

      manifest_path = stream.output_dir.join("manifest.m3u8")
      return unless manifest_path.exist?

      return if Scene.where(id: stream.scene_id).where.not(hls_segment_durations: nil).exists?

      durations = []
      File.foreach(manifest_path) do |line|
        if (m = line.match(/#EXTINF:([\d.]+),/))
          durations << m[1].to_f
        end
      end
      return if durations.empty?

      Scene.find(stream.scene_id).update_column(:hls_segment_durations, durations)
      Rails.logger.info "HLS StreamManager: saved #{durations.size} timestamps for scene #{stream.scene_id}"
    rescue ActiveRecord::RecordNotFound
      # Scene was deleted
    end

    def evict_cache_if_needed
      hls_root = Rails.root.join("tmp", "hls")
      return unless hls_root.exist?

      total_size = dir_size(hls_root)
      return if total_size <= MAX_CACHE_SIZE

      @mutex.synchronize do
        @cache_lru.each do |scene_id, _|
          break if total_size <= MAX_CACHE_SIZE

          # Don't evict scenes with active FFmpeg
          stream = @streams[scene_id]
          next if stream&.pid

          dir = hls_tmp_dir(scene_id)
          if dir.exist?
            freed = evict_scene_cache(dir)
            total_size -= freed
            Rails.logger.info "HLS StreamManager: evicted cache for scene #{scene_id} (#{(freed / 1024.0 / 1024).round(1)} MB freed)"
          end
          # Only fully remove from LRU if directory is gone
          unless dir.exist?
            @cache_lru.delete(scene_id)
            @streams.delete(scene_id)
          end
        end
      end
    end

    # Evict segments beyond the first KEEP_FIRST_SEGMENTS from a scene's cache dir.
    # If no segments worth keeping remain, removes the entire directory.
    # Returns bytes freed.
    def evict_scene_cache(dir)
      freed = 0
      segments = Dir[File.join(dir, "*.ts")]

      # Separate segments to keep vs remove
      keep = []
      remove = []
      segments.each do |f|
        n = File.basename(f)[/\A(\d+)\.ts\z/, 1]&.to_i
        if n && n < KEEP_FIRST_SEGMENTS
          keep << f
        else
          remove << f
        end
      end

      # Remove non-segment files (manifest, logs) and segments beyond threshold
      remove.each do |f|
        freed += File.size(f) rescue 0
        File.delete(f) rescue nil
      end

      # Also remove manifest and log files
      %w[manifest.m3u8 ffmpeg.log].each do |name|
        path = File.join(dir, name)
        if File.exist?(path)
          freed += File.size(path) rescue 0
          File.delete(path) rescue nil
        end
      end

      # If nothing kept, remove the directory
      if keep.empty?
        FileUtils.rm_rf(dir)
      end

      freed
    end

    def dir_size(path)
      Dir.glob(File.join(path, "**", "*"))
        .select { |f| File.file?(f) }
        .sum { |f| File.size(f) }
    rescue Errno::ENOENT
      0
    end
  end
end
