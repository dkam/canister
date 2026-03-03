FFMPEG.logger.level = Logger::WARN

module Canister
  TRANSCODE_DIRECTORY = ENV.fetch("TRANSCODE_PATH", Rails.root.join("transcodes").to_s)
  VALID_HTML5_CODECS = ["h264", "h265", "hevc", "vp8", "vp9", "av1"].freeze
  STREAMABLE_EXTENSIONS = %w[.mp4 .m4v .mov .webm].freeze

  # Metadata directories
  STASH_METADATA_DIRECTORY = ENV.fetch("STASH_PATH", Rails.root.join("metadata").to_s)
  STASH_SCENES_DIRECTORY = File.join(STASH_METADATA_DIRECTORY, "scenes")
  STASH_GALLERIES_DIRECTORY = File.join(STASH_METADATA_DIRECTORY, "galleries")
  STASH_PERFORMERS_DIRECTORY = File.join(STASH_METADATA_DIRECTORY, "performers")
  STASH_STUDIOS_DIRECTORY = File.join(STASH_METADATA_DIRECTORY, "studios")
  STASH_CACHE_DIRECTORY = File.join(STASH_METADATA_DIRECTORY, "cache")
  STASH_MAPPINGS_FILE = File.join(STASH_METADATA_DIRECTORY, "mappings.json")
  STASH_SCRAPED_FILE = File.join(STASH_METADATA_DIRECTORY, "scraped.json")

  # Generated content directories
  STASH_SCREENSHOTS_DIRECTORY = File.join(STASH_METADATA_DIRECTORY, "screenshots")
  STASH_VTT_DIRECTORY = File.join(STASH_METADATA_DIRECTORY, "vtt")
  STASH_MARKERS_DIRECTORY = File.join(STASH_METADATA_DIRECTORY, "markers")
  STASH_TRANSCODE_DIRECTORY = TRANSCODE_DIRECTORY
end
