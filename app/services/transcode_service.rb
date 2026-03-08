class TranscodeService
  def initialize(video:)
    @video = video
  end

  def start
    return if Canister::VALID_HTML5_CODECS.include?(@video.video_codec)
    return if has_transcode?

    FileUtils.mkdir_p(transcode_dir)

    Rails.logger.info("Video #{@video.id} is of type #{@video.video_codec}, transcoding...")
    movie = FFMPEG::Movie.new(@video.ffmpeg_input)
    percent = 0.0

    movie.transcode(temp_path, %w[-c:v libx264 -profile:v high -level 4.2 -preset superfast -crf 23 -vf scale=iw:-2 -c:a aac -movflags +faststart]) { |progress|
      rounded = progress.round(2)
      if rounded > percent
        Rails.logger.info("Progress: #{rounded}")
        percent = rounded
      end
    }

    FileUtils.mv(temp_path, transcode_path)

    @video
  end

  private

  def transcode_dir
    Canister::TRANSCODE_DIRECTORY
  end

  def temp_path
    File.join(transcode_dir, "#{@video.id}.tmp.mp4")
  end

  def transcode_path
    File.join(transcode_dir, "#{@video.id}.mp4")
  end

  def has_transcode?
    File.exist?(transcode_path)
  end
end
