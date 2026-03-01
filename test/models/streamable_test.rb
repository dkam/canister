require "test_helper"

class StreamableTest < ActiveSupport::TestCase
  def setup
    @scene = Scene.new(
      checksum: "test123",
      path: "/test/video.mp4",
      video_codec: "h264",
      audio_codec: "aac",
      title: "Test Scene"
    )
    allow_file_to_exist
  end

  def allow_file_to_exist
    allow(@scene).to receive(:stream_file_exists?).and_return(true)
  end

  test "available_streams includes direct stream for H264/AAC/MP4" do
    @scene.update(path: "/test/video.mp4", video_codec: "h264", audio_codec: "aac")

    streams = @scene.available_streams

    assert_equal 2, streams.length
    direct_stream = streams.find { |s| s[:kind] == :direct }
    assert_not_nil direct_stream
    assert_equal "Direct stream", direct_stream[:label]
    assert_equal "video/mp4", direct_stream[:mime_type]
    assert_equal :byte_range, direct_stream[:seek_mode]
    assert direct_stream[:video_copy]
    refute direct_stream[:audio_transcode]
  end

  test "available_streams includes direct stream for H264/MP3/MP4" do
    @scene.update(path: "/test/video.mp4", video_codec: "h264", audio_codec: "mp3")

    streams = @scene.available_streams

    assert_equal 2, streams.length
    direct_stream = streams.find { |s| s[:kind] == :direct }
    assert_not_nil direct_stream
    assert_equal "video/mp4", direct_stream[:mime_type]
  end

  test "available_streams includes direct stream for H264/AAC/M4V" do
    @scene.update(path: "/test/video.m4v", video_codec: "h264", audio_codec: "aac")

    streams = @scene.available_streams

    direct_stream = streams.find { |s| s[:kind] == :direct }
    assert_not_nil direct_stream
    assert_equal "video/mp4", direct_stream[:mime_type]
  end

  test "available_streams includes direct stream for H264/AAC/MOV" do
    @scene.update(path: "/test/video.mov", video_codec: "h264", audio_codec: "aac")

    streams = @scene.available_streams

    direct_stream = streams.find { |s| s[:kind] == :direct }
    assert_not_nil direct_stream
    assert_equal "video/mp4", direct_stream[:mime_type]
  end

  test "available_streams includes direct stream for VP8/Opus/WebM" do
    @scene.update(path: "/test/video.webm", video_codec: "vp8", audio_codec: "opus")

    streams = @scene.available_streams

    assert_equal 1, streams.length
    direct_stream = streams.find { |s| s[:kind] == :direct }
    assert_not_nil direct_stream
    assert_equal "video/webm", direct_stream[:mime_type]
    assert_equal :byte_range, direct_stream[:seek_mode]
  end

  test "available_streams includes direct stream for VP8/Vorbis/WebM" do
    @scene.update(path: "/test/video.webm", video_codec: "vp8", audio_codec: "vorbis")

    streams = @scene.available_streams

    direct_stream = streams.find { |s| s[:kind] == :direct }
    assert_not_nil direct_stream
    assert_equal "video/webm", direct_stream[:mime_type]
  end

  test "available_streams includes direct stream for VP9/Opus/WebM" do
    @scene.update(path: "/test/video.webm", video_codec: "vp9", audio_codec: "opus")

    streams = @scene.available_streams

    direct_stream = streams.find { |s| s[:kind] == :direct }
    assert_not_nil direct_stream
  end

  test "available_streams excludes direct stream for H264/Opus/MP4 (invalid audio for container)" do
    @scene.update(path: "/test/video.mp4", video_codec: "h264", audio_codec: "opus")

    streams = @scene.available_streams

    direct_stream = streams.find { |s| s[:kind] == :direct }
    assert_nil direct_stream
  end

  test "available_streams excludes direct stream for H264/Opus/WebM (invalid video for container)" do
    @scene.update(path: "/test/video.webm", video_codec: "h264", audio_codec: "opus")

    streams = @scene.available_streams

    direct_stream = streams.find { |s| s[:kind] == :direct }
    assert_nil direct_stream
  end

  test "available_streams excludes direct stream for H264/AAC/MKV (invalid container for browser)" do
    @scene.update(path: "/test/video.mkv", video_codec: "h264", audio_codec: "aac")

    streams = @scene.available_streams

    direct_stream = streams.find { |s| s[:kind] == :direct }
    assert_nil direct_stream
  end

  test "available_streams excludes direct stream for H264/Vorbis/MP4 (invalid audio for container)" do
    @scene.update(path: "/test/video.mp4", video_codec: "h264", audio_codec: "vorbis")

    streams = @scene.available_streams

    direct_stream = streams.find { |s| s[:kind] == :direct }
    assert_nil direct_stream
  end

  test "available_streams includes MP4 progressive stream for H264" do
    @scene.update(video_codec: "h264", audio_codec: "aac")

    streams = @scene.available_streams

    mp4_stream = streams.find { |s| s[:kind] == :progressive }
    assert_not_nil mp4_stream
    assert_equal "MP4 (H.264 copy)", mp4_stream[:label]
    assert_equal "video/mp4", mp4_stream[:mime_type]
    assert_equal :timestamp, mp4_stream[:seek_mode]
    assert mp4_stream[:video_copy]
    refute mp4_stream[:audio_transcode]
  end

  test "available_streams includes MP4 progressive stream for H264 with audio transcode" do
    @scene.update(video_codec: "h264", audio_codec: "opus")

    streams = @scene.available_streams

    mp4_stream = streams.find { |s| s[:kind] == :progressive }
    assert_not_nil mp4_stream
    assert_equal "MP4 (H.264 copy) AAC transcode", mp4_stream[:label]
    assert mp4_stream[:video_copy]
    assert mp4_stream[:audio_transcode]
  end

  test "available_streams includes MP4 progressive stream for H265" do
    @scene.update(video_codec: "h265", audio_codec: "aac")

    streams = @scene.available_streams

    mp4_stream = streams.find { |s| s[:kind] == :progressive }
    assert_not_nil mp4_stream
    assert_equal "MP4", mp4_stream[:label]
    refute mp4_stream[:video_copy]
    refute mp4_stream[:audio_transcode]
  end

  test "available_streams includes MP4 progressive stream for VP8 with audio transcode" do
    @scene.update(video_codec: "vp8", audio_codec: "opus")

    streams = @scene.available_streams

    mp4_stream = streams.find { |s| s[:kind] == :progressive }
    assert_not_nil mp4_stream
    assert_equal "MP4 AAC transcode", mp4_stream[:label]
    refute mp4_stream[:video_copy]
    assert mp4_stream[:audio_transcode]
  end

  test "available_streams includes MP4 progressive stream for VP9 with audio transcode" do
    @scene.update(video_codec: "vp9", audio_codec: "vorbis")

    streams = @scene.available_streams

    mp4_stream = streams.find { |s| s[:kind] == :progressive }
    assert_not_nil mp4_stream
    assert_equal "MP4 AAC transcode", mp4_stream[:label]
    refute mp4_stream[:video_copy]
    assert mp4_stream[:audio_transcode]
  end

  test "available_streams includes MP4 progressive stream for VP9 with AAC" do
    @scene.update(video_codec: "vp9", audio_codec: "aac")

    streams = @scene.available_streams

    mp4_stream = streams.find { |s| s[:kind] == :progressive }
    assert_not_nil mp4_stream
    assert_equal "MP4", mp4_stream[:label]
    refute mp4_stream[:video_copy]
    refute mp4_stream[:audio_transcode]
  end

  test "available_streams excludes MP4 progressive stream for unsupported video codec" do
    @scene.update(video_codec: "unreal", audio_codec: "aac")

    streams = @scene.available_streams

    mp4_stream = streams.find { |s| s[:kind] == :progressive }
    assert_nil mp4_stream
  end

  test "available_streams includes MP4 progressive stream for AV1" do
    @scene.update(video_codec: "av1", audio_codec: "aac")

    streams = @scene.available_streams

    mp4_stream = streams.find { |s| s[:kind] == :progressive }
    assert_not_nil mp4_stream
    assert_equal "MP4", mp4_stream[:label]
    refute mp4_stream[:video_copy]
    refute mp4_stream[:audio_transcode]
  end

  test "available_streams handles missing audio codec" do
    @scene.update(video_codec: "h264", audio_codec: "")

    streams = @scene.available_streams

    assert_equal 2, streams.length
    direct_stream = streams.find { |s| s[:kind] == :direct }
    assert_not_nil direct_stream

    mp4_stream = streams.find { |s| s[:kind] == :progressive }
    assert_not_nil mp4_stream
    assert_equal "MP4 (H.264 copy)", mp4_stream[:label]
    assert mp4_stream[:audio_transcode]
  end

  test "direct_streamable? returns true for H264/AAC/MP4" do
    @scene.update(path: "/test/video.mp4", video_codec: "h264", audio_codec: "aac")
    allow(@scene).to receive(:stream_file_exists?).and_return(true)

    assert @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns true for H264/AAC/M4V" do
    @scene.update(path: "/test/video.m4v", video_codec: "h264", audio_codec: "aac")
    allow(@scene).to receive(:stream_file_exists?).and_return(true)

    assert @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns true for H264/AAC/MOV" do
    @scene.update(path: "/test/video.mov", video_codec: "h264", audio_codec: "aac")
    allow(@scene).to receive(:stream_file_exists?).and_return(true)

    assert @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns true for VP8/Opus/WebM" do
    @scene.update(path: "/test/video.webm", video_codec: "vp8", audio_codec: "opus")
    allow(@scene).to receive(:stream_file_exists?).and_return(true)

    assert @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns false for H264/Opus/MP4" do
    @scene.update(path: "/test/video.mp4", video_codec: "h264", audio_codec: "opus")
    allow(@scene).to receive(:stream_file_exists?).and_return(true)

    refute @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns false for H264/AAC/MKV" do
    @scene.update(path: "/test/video.mkv", video_codec: "h264", audio_codec: "aac")
    allow(@scene).to receive(:stream_file_exists?).and_return(true)

    refute @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns false for H264/AAC/AVI" do
    @scene.update(path: "/test/video.avi", video_codec: "h264", audio_codec: "aac")
    allow(@scene).to receive(:stream_file_exists?).and_return(true)

    refute @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns false for unsupported video codec" do
    @scene.update(path: "/test/video.mp4", video_codec: "unreal", audio_codec: "aac")
    allow(@scene).to receive(:stream_file_exists?).and_return(true)

    refute @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns false when file doesn't exist" do
    @scene.update(path: "/test/video.mp4", video_codec: "h264", audio_codec: "aac")
    allow(@scene).to receive(:stream_file_exists?).and_return(false)

    refute @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns true for H264/AAC/M4V" do
    @scene.update(path: "/test/video.m4v", video_codec: "h264", audio_codec: "aac")

    assert @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns true for H264/AAC/MOV" do
    @scene.update(path: "/test/video.mov", video_codec: "h264", audio_codec: "aac")

    assert @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns true for VP8/Opus/WebM" do
    @scene.update(path: "/test/video.webm", video_codec: "vp8", audio_codec: "opus")

    assert @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns false for H264/Opus/MP4" do
    @scene.update(path: "/test/video.mp4", video_codec: "h264", audio_codec: "opus")

    refute @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns false for H264/AAC/MKV" do
    @scene.update(path: "/test/video.mkv", video_codec: "h264", audio_codec: "aac")

    refute @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns false for H264/AAC/AVI" do
    @scene.update(path: "/test/video.avi", video_codec: "h264", audio_codec: "aac")

    refute @scene.send(:direct_streamable?)
  end

  test "direct_streamable? returns false for unsupported video codec" do
    @scene.update(path: "/test/video.mp4", video_codec: "av1", audio_codec: "aac")

    refute @scene.send(:direct_streamable?)
  end

  test "build_mp4_stream returns nil for unsupported video codec" do
    @scene.update(video_codec: "unreal", audio_codec: "aac")

    result = @scene.send(:build_mp4_stream)

    assert_nil result
  end

  test "build_mp4_stream sets video_copy true for H264" do
    @scene.update(video_codec: "h264", audio_codec: "aac")

    result = @scene.send(:build_mp4_stream)

    assert_not_nil result
    assert result[:video_copy]
  end

  test "build_mp4_stream sets video_copy false for H265" do
    @scene.update(video_codec: "h265", audio_codec: "aac")

    result = @scene.send(:build_mp4_stream)

    assert_not_nil result
    refute result[:video_copy]
  end

  test "build_mp4_stream sets audio_copy true for AAC" do
    @scene.update(video_codec: "h264", audio_codec: "aac")

    result = @scene.send(:build_mp4_stream)

    assert_not_nil result
    refute result[:audio_transcode]
  end

  test "build_mp4_stream sets audio_copy true for MP3" do
    @scene.update(video_codec: "h264", audio_codec: "mp3")

    result = @scene.send(:build_mp4_stream)

    assert_not_nil result
    refute result[:audio_transcode]
  end

  test "build_mp4_stream sets audio_transcode true for Opus" do
    @scene.update(video_codec: "h264", audio_codec: "opus")

    result = @scene.send(:build_mp4_stream)

    assert_not_nil result
    assert result[:audio_transcode]
  end

  test "build_mp4_stream sets audio_transcode true for Vorbis" do
    @scene.update(video_codec: "h264", audio_codec: "vorbis")

    result = @scene.send(:build_mp4_stream)

    assert_not_nil result
    assert result[:audio_transcode]
  end

  test "build_mp4_stream sets audio_transcode true for missing audio" do
    @scene.update(video_codec: "h264", audio_codec: "")

    result = @scene.send(:build_mp4_stream)

    assert_not_nil result
    assert result[:audio_transcode]
    assert_equal "MP4 (H.264 copy)", result[:label]
  end

  test "build_mp4_stream label for H264 copy only" do
    @scene.update(video_codec: "h264", audio_codec: "aac")

    result = @scene.send(:build_mp4_stream)

    assert_equal "MP4 (H.264 copy)", result[:label]
  end

  test "build_mp4_stream label for H264 copy with audio transcode" do
    @scene.update(video_codec: "h264", audio_codec: "opus")

    result = @scene.send(:build_mp4_stream)

    assert_equal "MP4 (H.264 copy) AAC transcode", result[:label]
  end

  test "build_mp4_stream label for full transcode" do
    @scene.update(video_codec: "h265", audio_codec: "aac")

    result = @scene.send(:build_mp4_stream)

    assert_equal "MP4", result[:label]
  end

  test "build_mp4_stream label for audio transcode only" do
    @scene.update(video_codec: "h265", audio_codec: "opus")

    result = @scene.send(:build_mp4_stream)

    assert_equal "MP4 AAC transcode", result[:label]
  end
end
