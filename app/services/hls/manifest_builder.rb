module Hls
  class ManifestBuilder
    # Build an estimated manifest with uniform segment durations.
    # Single-process model: no discontinuity tags needed since all segments
    # come from one FFmpeg encode (killed and restarted on seek).
    def self.resolve(video, config, &url_builder)
      estimated(video.duration.to_f, &url_builder)
    end

    def self.estimated(duration, &url_builder)
      segment_duration = Hls::StreamManager::SEGMENT_DURATION
      segment_count = (duration / segment_duration).ceil
      last_duration = duration - ((segment_count - 1) * segment_duration)

      lines = [
        "#EXTM3U",
        "#EXT-X-VERSION:3",
        "#EXT-X-MEDIA-SEQUENCE:0",
        "#EXT-X-TARGETDURATION:#{segment_duration}",
        "#EXT-X-PLAYLIST-TYPE:VOD"
      ]

      (0...segment_count).each do |i|
        seg_dur = (i == segment_count - 1) ? last_duration : segment_duration.to_f
        lines << "#EXTINF:#{format("%.3f", seg_dur)},"
        lines << url_builder.call(i)
      end

      lines << "#EXT-X-ENDLIST"
      lines.join("\n")
    end
  end
end
