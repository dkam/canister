module Hls
  class FfmpegCommand
    # Build FFmpeg command for HLS transcode.
    # Single process per video — runs until killed or EOF.
    # Produces manifest.m3u8 + dotfile segments (.N.ts).
    def self.build(input:, output_dir:, config:, from_segment: 0)
      cmd = base_cmd
      cmd += ["-ss", (from_segment * Hls::StreamManager::SEGMENT_DURATION).to_s] if from_segment > 0
      cmd += ["-i", input]
      cmd += video_opts(config)
      cmd += audio_opts(config)
      cmd += %w[-sn -copyts -avoid_negative_ts disabled]

      cmd += [
        "-f", "hls",
        "-start_number", from_segment.to_s,
        "-hls_time", Hls::StreamManager::SEGMENT_DURATION.to_s,
        "-hls_flags", "split_by_time",
        "-hls_segment_type", "mpegts",
        "-hls_playlist_type", "vod",
        "-hls_segment_filename", output_dir.join(".%d.ts").to_s,
        output_dir.join("manifest.m3u8").to_s
      ]

      cmd
    end

    def self.base_cmd
      %w[ffmpeg -hide_banner -loglevel error]
    end
    private_class_method :base_cmd

    def self.video_opts(config)
      if config[:video_copy]
        %w[-c:v copy -bsf:v h264_mp4toannexb]
      else
        %w[-flags +cgop -force_key_frames expr:gte(t,n_forced*2) -c:v libx264 -preset veryfast -crf 23]
      end
    end
    private_class_method :video_opts

    def self.audio_opts(config)
      if config[:audio_transcode]
        %w[-c:a aac -ac 2]
      else
        %w[-c:a copy]
      end
    end
    private_class_method :audio_opts
  end
end
