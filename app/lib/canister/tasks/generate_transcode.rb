class Canister::Tasks::GenerateTranscode < Canister::Tasks::Base
  def initialize(scene:)
    super()
    @scene = scene
  end

  def start
    return if Canister::VALID_HTML5_CODECS.include?(@scene.video_codec)
    return if has_transcode?

    FileUtils.mkdir_p(transcode_dir)

    @manager.info("#{@scene.checksum} is of type #{@scene.video_codec}, transcoding...")
    video = FFMPEG::Movie.new(@scene.path)
    percent = 0.0

    video.transcode(temp_path, %w(-c:v libx264 -profile:v high -level 4.2 -preset superfast -crf 23 -vf scale=iw:-2 -c:a aac)) { |progress|
      rounded = progress.round(2)
      if rounded > percent
        @manager.info("Progress: #{rounded}")
        percent = rounded
      end
    }

    FileUtils.mv(temp_path, transcode_path)

    return @scene
  end

  private

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
