class Canister::Tasks::Scan < Canister::Tasks::Base
  def initialize(path:, library:)
    super()
    @path = path
    @library = library
    @backend = library&.backend
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

    existing_item = Checksum.find_by(hash_value: checksum, checksum_type: :opensubtitles, hashable_type: @klass.to_s)&.hashable

    if existing_item
      @manager.info("#{@path} already exists.  Updating path...")
      existing_item.update(path: @path)
      begin
        make_screenshot(existing_item) if existing_item.is_a?(Scene) && existing_item.screenshots.none?
      rescue => e
        @manager.error("Error encountered generating screenshot for #{@path}: #{e.message}")
      end
      return nil
    end

    @manager.info("#{@path} doesn't exist.  Creating new item...")
    item = @klass.new(path: @path, library: (@library if @klass == Scene))

    if @klass == Scene
      ffmpeg_path = @backend ? @backend.ffmpeg_input(@path) : @path
      video = FFMPEG::Movie.new(ffmpeg_path)
      item.size = video.size
      item.duration = video.duration
      item.video_codec = video.video_codec
      item.audio_codec = video.audio_codec
      item.width = video.width
      item.height = video.height
      item.framerate = video.frame_rate
      item.bitrate = video.bitrate
      item.checksums.build(checksum_type: :opensubtitles, hash_value: checksum)
    else
      item.checksums.build(checksum_type: :opensubtitles, hash_value: checksum)
    end

    item.save!

    begin
      make_screenshot(item) if @klass == Scene
    rescue => e
      @manager.error("Error encountered generating screenshot for #{@path}: #{e.message}")
    end

    @path
  end

  private

  def path_class
    (File.extname(@path) == ".zip") ? Gallery : Scene
  end

  def calculate_checksum
    @manager.info("#{@path} not found.  Calculating checksum...")

    require "open_subtitles_hash"

    absolute_path = @backend&.absolute_path(@path) || @path

    if @backend&.local? || @backend.nil?
      OpenSubtitlesHash.compute_hash(absolute_path).downcase
    else
      calculate_remote_opensubtitles_hash
    end
  end

  def calculate_remote_opensubtitles_hash
    first_64k = @backend.read_range(@path, 0)
    file_size = @backend.file_size(@path)

    return "0" * 16 unless first_64k && file_size

    last_64k = @backend.read_range(@path, file_size - 65536..file_size - 1)
    return "0" * 16 unless last_64k

    data = first_64k + last_64k

    sum = 0
    data.unpack("Q<*").each { |n| sum += n }

    ((sum + file_size) & 0xffffffffffffffff).to_s(16).downcase.rjust(16, "0")
  end

  def make_screenshot(scene)
    ffmpeg_path = @backend ? @backend.ffmpeg_input(scene.path) : scene.path
    video = FFMPEG::Movie.new(ffmpeg_path)
    timecode = video.duration * 0.2

    Tempfile.create(["screenshot", ".jpg"]) do |tmp|
      transcoder_options = {input_options: {v: "quiet", ss: timecode.to_s}}
      options = {screenshot: true, quality: 2, custom: %W[-vf scale=#{video.width}:-1]}
      video.transcode(tmp.path, options, transcoder_options)

      screenshot = scene.screenshots.build(timecode: timecode)
      screenshot.image.attach(
        io: File.open(tmp.path),
        filename: "screenshot_#{(timecode * 1000).to_i}ms.jpg",
        content_type: "image/jpeg"
      )
      screenshot.save!
    end
  end
end
