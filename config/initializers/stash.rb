FFMPEG.logger.level = Logger::WARN

module Canister
  TRANSCODE_DIRECTORY = ENV.fetch('TRANSCODE_PATH', Rails.root.join('transcodes').to_s)
  VALID_HTML5_CODECS = ["h264", "h265", "vp8", "vp9"].freeze
  STREAMABLE_EXTENSIONS = %w[.mp4 .m4v .mov .webm].freeze
end
