class Canister::Tasks::PrepareVideo
  def initialize(scene:)
    @scene = scene
  end

  def start
    return if has_transcode?
    return if already_streamable?

    if remuxable?
      Rails.logger.info("[PrepareVideo] Remuxing #{@scene.checksum} (#{@scene.video_codec} in #{File.extname(@scene.path)})")
      remux
    else
      Rails.logger.info("[PrepareVideo] Transcoding #{@scene.checksum} (#{@scene.video_codec})")
      transcode
    end
  end

  private

    def remuxable?
      Canister::VALID_HTML5_CODECS.include?(@scene.video_codec)
    end

    def already_streamable?
      remuxable? && Canister::STREAMABLE_EXTENSIONS.include?(File.extname(@scene.path).downcase)
    end

    def remux
      FileUtils.mkdir_p(transcode_dir)
      movie = FFMPEG::Movie.new(@scene.path)
      movie.transcode(temp_path, %w(-c copy -movflags +faststart))
      FileUtils.mv(temp_path, transcode_path)
    end

    def transcode
      FileUtils.mkdir_p(transcode_dir)
      movie = FFMPEG::Movie.new(@scene.path)
      movie.transcode(temp_path, %w(-c:v libx264 -profile:v high -level 4.2 -preset superfast -crf 23 -vf scale=iw:-2 -c:a aac -movflags +faststart))
      FileUtils.mv(temp_path, transcode_path)
    end

    def transcode_dir
      Canister::TRANSCODE_DIRECTORY
    end

    def temp_path
      File.join(transcode_dir, "#{@scene.checksum}.tmp.mp4")
    end

    def transcode_path
      File.join(transcode_dir, "#{@scene.checksum}.mp4")
    end

    def has_transcode?
      File.exist?(transcode_path)
    end
end
