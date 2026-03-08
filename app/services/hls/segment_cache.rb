module Hls
  class SegmentCache
    KEEP_FIRST_SEGMENTS = 15
    MAX_CACHE_SIZE = (ENV.fetch("HLS_MAX_CACHE_SIZE_GB", "5").to_f * 1024 * 1024 * 1024).to_i

    def initialize
      @lru = {} # video_id => Time (Ruby Hash preserves insertion order)
      populate_lru
    end

    def hls_dir(video_id)
      Rails.root.join("tmp", "hls", video_id.to_s)
    end

    def segment_exists?(video_id, segment_idx)
      hls_dir(video_id).join("#{segment_idx}.ts").exist?
    end

    def touch(video_id)
      @lru.delete(video_id)
      @lru[video_id] = Time.now
    end

    def ensure_dir(video_id)
      dir = hls_dir(video_id)
      FileUtils.mkdir_p(dir)
      dir
    end

    # Evict LRU videos until under MAX_CACHE_SIZE.
    # skip_video_ids: set of video IDs with active primary processes.
    def evict_if_needed(skip_video_ids: Set.new)
      hls_root = Rails.root.join("tmp", "hls")
      return unless hls_root.exist?

      total_size = dir_size(hls_root)
      return if total_size <= MAX_CACHE_SIZE

      @lru.each do |video_id, _|
        break if total_size <= MAX_CACHE_SIZE
        next if skip_video_ids.include?(video_id)

        dir = hls_dir(video_id)
        if dir.exist?
          freed = evict_video(dir)
          total_size -= freed
          Rails.logger.info "HLS SegmentCache: evicted video #{video_id} (#{(freed / 1024.0 / 1024).round(1)} MB freed)"
        end

        unless dir.exist?
          @lru.delete(video_id)
        end
      end
    end

    private

    def populate_lru
      hls_root = Rails.root.join("tmp", "hls")
      return unless hls_root.exist?

      Dir.children(hls_root)
        .map { |d| [d, hls_root.join(d)] }
        .select { |_, p| File.directory?(p) }
        .sort_by { |_, p| File.mtime(p) }
        .each { |id, _| @lru[id] = Time.now }
    end

    def evict_video(dir)
      freed = 0
      segments = Dir[File.join(dir, "*.ts")]

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

      remove.each do |f|
        freed += File.size(f) rescue 0
        File.delete(f) rescue nil
      end

      %w[manifest.m3u8 ffmpeg.log].each do |name|
        path = File.join(dir, name)
        if File.exist?(path)
          freed += File.size(path) rescue 0
          File.delete(path) rescue nil
        end
      end

      FileUtils.rm_rf(dir) if keep.empty?

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
