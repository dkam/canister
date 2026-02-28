class Canister::Tasks::Scan < Canister::Tasks::Base
  def initialize(path:, library:)
    super()
    @path = path
    @library = library
  end

  def start
    @manager = Canister::Manager.instance
    @klass = path_class

    item = @klass.find_by(path: @path)
    if item
      make_screenshot(item) if @klass == Scene && item.screenshots.none?
      return nil
    end

    checksum = calculate_checksum

    item = @klass.find_by(checksum: checksum)
    if item
      @manager.info("#{@path} already exists.  Updating path...")
      item.path = @path
      item.save
    else
      @manager.info("#{@path} doesn't exist.  Creating new item...")
      item = @klass.new(path: @path, checksum: checksum, library: (@library if @klass == Scene))

      if @klass == Scene
        video = FFMPEG::Movie.new(@path)
        item.size        = video.size
        item.duration    = video.duration
        item.video_codec = video.video_codec
        item.audio_codec = video.audio_codec
        item.width       = video.width
        item.height      = video.height
        item.framerate   = video.frame_rate
        item.bitrate     = video.bitrate
      end

      item.save
    end

    begin
      make_screenshot(item) if @klass == Scene
    rescue => e
      @manager.error("Error encountered generating screenshot for #{@path}: #{e.message}")
    end

    return @path
  end

  private

    def path_class
      File.extname(@path) == '.zip' ? Gallery : Scene
    end

    def calculate_checksum
      @manager.info("#{@path} not found.  Calculating checksum...")
      checksum = Digest::MD5.file(@path).hexdigest
      @manager.debug("Checksum calculated: #{checksum}")
      checksum
    end

    def make_screenshot(scene)
      video = FFMPEG::Movie.new(scene.path)
      timecode = video.duration * 0.2

      Tempfile.create(['screenshot', '.jpg']) do |tmp|
        transcoder_options = { input_options: { v: 'quiet', ss: timecode.to_s } }
        options = { screenshot: true, quality: 2, custom: %W(-vf scale=#{video.width}:-1) }
        video.transcode(tmp.path, options, transcoder_options)

        screenshot = scene.screenshots.build(timecode: timecode)
        screenshot.image.attach(
          io: File.open(tmp.path),
          filename: "screenshot_#{(timecode * 1000).to_i}ms.jpg",
          content_type: 'image/jpeg'
        )
        screenshot.save!
      end
    end
end
