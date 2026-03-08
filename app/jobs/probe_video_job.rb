require "open3"

class ProbeVideoJob < ApplicationJob
  queue_as :media

  def perform(video_id)
    Video.find(video_id).probe!
  end

  def self.ffprobe(path)
    command = [
      FFMPEG.ffprobe_binary,
      "-probesize", "1M",
      "-analyzeduration", "1M",
      "-i", path,
      "-print_format", "json",
      "-show_format", "-show_streams", "-show_error"
    ]

    stdout, _stderr, _status = Open3.capture3(*command)
    data = JSON.parse(stdout, symbolize_names: true)

    video_stream = data[:streams]&.find { |s| s[:codec_type] == "video" }
    audio_stream = data[:streams]&.find { |s| s[:codec_type] == "audio" }
    format = data[:format] || {}

    framerate = if video_stream && video_stream[:avg_frame_rate] != "0/0"
                  Rational(video_stream[:avg_frame_rate]).to_f
                end

    {
      duration: format[:duration]&.to_f,
      bitrate: format[:bit_rate]&.to_i,
      video_codec: video_stream&.dig(:codec_name),
      audio_codec: audio_stream&.dig(:codec_name),
      width: video_stream&.dig(:width),
      height: video_stream&.dig(:height),
      framerate: framerate
    }
  end
end
