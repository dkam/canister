class Canister::Tasks::PrepareVideo < Canister::Tasks::Base
  def initialize(scene:)
    super()
    @scene = scene
  end

  def start
    return if has_transcode?
    return if Canister::VALID_HTML5_CODECS.include?(@scene.video_codec)

    @manager.info("Transcoding Scene #{@scene.id} (#{@scene.video_codec})")
    transcode
  end

  private

  def transcode
    FileUtils.mkdir_p(transcode_dir)
    movie = FFMPEG::Movie.new(@scene.ffmpeg_input)
    movie.transcode(temp_path, %w[-c:v libx264 -profile:v high -level 4.2 -preset superfast -crf 23 -vf scale=iw:-2 -c:a aac -movflags +faststart])
    FileUtils.mv(temp_path, transcode_path)
  end

  def transcode_dir
    Canister::TRANSCODE_DIRECTORY
  end

  def temp_path
    File.join(transcode_dir, "#{@scene.id}.tmp.mp4")
  end

  def transcode_path
    File.join(transcode_dir, "#{@scene.id}.mp4")
  end

  def has_transcode?
    File.exist?(transcode_path)
  end
end
