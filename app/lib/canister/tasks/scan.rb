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

    checksums = calculate_checksum

    # Check for existing item by opensubtitles hash (scenes) or xxhash (galleries)
    existing_item = if @klass == Scene
      Checksum.joins(:hashable)
        .find_by(hash_value: checksums[:opensubtitles], checksum_type: :opensubtitles, hashable_type: "Scene")
        &.hashable
    else
      Checksum.joins(:hashable)
        .find_by(hash_value: checksums[:xxhash], checksum_type: :xxhash, hashable_type: "Gallery")
        &.hashable
    end

    if existing_item
      @manager.info("#{@path} already exists.  Updating path...")
      existing_item.update(path: @path)
      make_screenshot(existing_item) if existing_item.is_a?(Scene) && existing_item.screenshots.none?
      return nil
    end

    @manager.info("#{@path} doesn't exist.  Creating new item...")
    item = @klass.new(path: @path, library: (@library if @klass == Scene))

    if @klass == Scene
      video = FFMPEG::Movie.new(@path)
      item.size = video.size
      item.duration = video.duration
      item.video_codec = video.video_codec
      item.audio_codec = video.audio_codec
      item.width = video.width
      item.height = video.height
      item.framerate = video.frame_rate
      item.bitrate = video.bitrate
    end

    item.save!

    # Create checksum records
    if @klass == Scene
      Checksum.create!(hashable: item, checksum_type: :opensubtitles, hash_value: checksums[:opensubtitles])
      Checksum.create!(hashable: item, checksum_type: :xxhash, hash_value: checksums[:xxhash])
    else
      Checksum.create!(hashable: item, checksum_type: :xxhash, hash_value: checksums[:xxhash])
    end

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
    @manager.info("#{@path} not found.  Calculating checksums...")

    require_relative "../../../open_subtitles_hash"

    # For scenes: calculate both opensubtitles and xxhash
    if @klass == Scene
      os_hash = OpenSubtitlesHash.compute_hash(@path).downcase
      xxhash_value = XXhash.xxh64(File.binread(@path)).to_s(16)
      @manager.debug("Checksums calculated - OS: #{os_hash}, XXHash: #{xxhash_value}")
      {opensubtitles: os_hash, xxhash: xxhash_value}
    # For galleries: calculate only xxhash
    else
      checksum = XXhash.xxh64(File.binread(@path)).to_s(16)
      @manager.debug("Checksum calculated - XXHash: #{checksum}")
      {xxhash: checksum}
    end
  end

  def make_screenshot(scene)
    video = FFMPEG::Movie.new(scene.path)
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
