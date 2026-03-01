module Streamable
  extend ActiveSupport::Concern

  # Returns an ordered list of available stream descriptors.
  # URLs are intentionally omitted — the caller (controller/view) resolves those.
  #
  # Each entry: { kind:, mime_type:, label:, seekable: }
  #   kind:     :direct — byte-range serve of the source/transcode file
  #             :live   — FFmpeg pipe (fragmented MP4, seeks via ?start=)
  def available_streams
    streams = []

    if is_streamable
      ext = File.extname(stream_file_path).downcase
      mime = ext == ".webm" ? "video/webm" : "video/mp4"
      streams << { kind: :direct, mime_type: mime, label: "Direct stream", seek_mode: :byte_range }
    end

    streams << { kind: :live, mime_type: "video/mp4", label: "Live remux", seek_mode: :timestamp }

    streams
  end
end
