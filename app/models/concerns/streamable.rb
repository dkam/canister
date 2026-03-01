module Streamable
  extend ActiveSupport::Concern

  # Returns an ordered list of available stream descriptors.
  # URLs are intentionally omitted — the caller (controller/view) resolves those.
  #
  # Each entry: { kind:, mime_type:, label:, seek_mode:, video_copy:, audio_transcode: }
  #   kind:     :direct — byte-range serve of source/transcode file
  #             :progressive — FFmpeg pipe (fragmented MP4/WebM, seeks via ?start=)
  def available_streams
    streams = []

    if direct_streamable?
      ext = File.extname(stream_file_path).downcase
      mime = (ext == ".webm") ? "video/webm" : "video/mp4"
      streams << {kind: :direct, mime_type: mime, label: "Direct stream", seek_mode: :byte_range, video_copy: true, audio_transcode: false}
    end

    hls_stream = build_hls_stream
    streams << hls_stream if hls_stream

    mp4_stream = build_mp4_stream
    streams << mp4_stream if mp4_stream

    streams
  end

  private

  def direct_streamable?
    return false unless stream_file_exists?

    case File.extname(stream_file_path).downcase
    when ".mp4", ".m4v", ".mov"
      video_codec.in?(Canister::VALID_HTML5_CODECS) &&
        audio_codec.in?(%w[aac mp3])
    when ".webm"
      video_codec.in?(%w[vp8 vp9]) &&
        audio_codec.in?(%w[opus vorbis])
    else
      false
    end
  end

  def stream_file_exists?
    File.exist?(transcode_path) || File.exist?(path)
  end

  def build_hls_stream
    return nil unless video_codec.in?(Canister::VALID_HTML5_CODECS)

    {
      kind: :hls,
      mime_type: "application/vnd.apple.mpegurl",
      label: "HLS",
      seek_mode: :hls,
      video_copy: video_codec == "h264",
      audio_transcode: !audio_codec.in?(%w[aac mp3])
    }
  end

  def build_mp4_stream
    return nil unless video_codec.in?(Canister::VALID_HTML5_CODECS)

    video_copy = video_codec == "h264"
    audio_copy = audio_codec.in?(%w[aac mp3])

    label_parts = []
    label_parts << "MP4"
    label_parts << "(H.264 copy)" if video_copy
    label_parts << "AAC transcode" if !audio_copy && audio_codec.present?

    {
      kind: :progressive,
      mime_type: "video/mp4",
      label: label_parts.join(" "),
      seek_mode: :timestamp,
      video_copy: video_copy,
      audio_transcode: !audio_copy
    }
  end
end
