require "singleton"

module Hls
  class StreamManager
    include Singleton

    SEGMENT_DURATION = 2       # seconds per segment
    SEGMENT_WAIT_TIMEOUT = 15  # max seconds to wait for segment file
    MAX_SEGMENT_GAP = 5        # kill process if request > this many segments ahead
    MAX_SEGMENT_BUFFER = 15    # stop transcode when this many segments buffered ahead
    MONITOR_INTERVAL = 0.2     # background check frequency (seconds)
    MAX_IDLE_TIME = 30         # seconds before idle transcode is stopped

    attr_reader :cache

    def initialize
      @mutex = Mutex.new
      @cv = ConditionVariable.new
      @streams = {} # video_id => TranscodeProcess
      @cache = SegmentCache.new
      @monitor_thread = nil
      @shutting_down = false
    end

    # Called from stream_hls_segment — returns :ok or :not_found.
    def request_segment(video, segment_idx, config)
      hls_dir = @cache.hls_dir(video.id)
      segment_path = hls_dir.join("#{segment_idx}.ts")

      # Fast path: segment already on disk
      if segment_path.exist?
        @mutex.synchronize do
          tp = @streams[video.id]
          tp&.touch(segment_idx)
          @cache.touch(video.id)
        end
        return :ok
      end

      @mutex.synchronize do
        @cache.touch(video.id)
        tp = @streams[video.id]

        if tp.nil? || !tp.running?
          # No process running — start from requested segment
          tp = ensure_transcode(video, config)
          tp.start(video, config, segment_idx, @cache)
          ensure_monitor_running
        elsif needs_restart?(tp, segment_idx)
          # Process running but segment is behind or too far ahead — kill and restart
          Rails.logger.info "HLS StreamManager: restarting for video #{video.id} (requested #{segment_idx}, highest #{tp.highest_generated})"
          tp.stop
          tp.start(video, config, segment_idx, @cache)
        else
          # Process is running and will reach this segment — just wait
          tp.touch(segment_idx)
        end

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

    def shutdown
      @mutex.synchronize do
        @shutting_down = true
        @streams.each_value(&:stop)
        @cv.broadcast
      end
      @monitor_thread&.join(10)
    end

    private

    def ensure_transcode(video, config)
      @streams[video.id] ||= TranscodeProcess.new
    end

    def needs_restart?(tp, segment_idx)
      highest = tp.highest_generated
      return false if highest == -1 # Just started, give it time

      # Segment is behind what we've already generated — need to seek back
      return true if segment_idx <= highest

      # Segment is too far ahead — kill and restart closer
      gap = segment_idx - highest
      gap > MAX_SEGMENT_GAP
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
        broadcast = false

        @mutex.synchronize do
          @streams.each do |video_id, tp|
            next unless tp.stream

            # Monitor tick: rename dotfiles, detect exit
            broadcast = true if tp.monitor_tick

            # Buffer limit: stop transcode if enough segments buffered ahead
            if tp.running? && buffer_full?(tp)
              Rails.logger.debug "HLS StreamManager: buffer full for video #{video_id}, pausing transcode"
              tp.stop
            end

            # Idle cleanup: stop transcode if no activity
            if tp.running? && tp.idle_seconds > MAX_IDLE_TIME
              Rails.logger.info "HLS StreamManager: idle timeout for video #{video_id}"
              tp.stop
            end
          end

          @cv.broadcast if broadcast

          # Evict cache (skip videos with active transcodes)
          active_ids = @streams.select { |_, tp| tp.running? }.keys.to_set
          @cache.evict_if_needed(skip_video_ids: active_ids)
        end

        sleep MONITOR_INTERVAL
      end
    end

    # Check if MAX_SEGMENT_BUFFER segments ahead of the last requested segment exist on disk.
    # This matches Stash's checkTranscode: stop encoding when we're far enough ahead of playback.
    def buffer_full?(tp)
      return false unless tp.stream

      last_requested = tp.last_requested_segment
      dir = tp.stream.output_dir
      (last_requested..last_requested + MAX_SEGMENT_BUFFER).all? { |i| dir.join("#{i}.ts").exist? }
    end
  end
end
