class GenerateSpriteService
  COLUMNS = 9
  ROWS = 9
  THUMB_COUNT = COLUMNS * ROWS # 81
  THUMB_WIDTH = 160

  def initialize(video:)
    @video = video
  end

  def start
    return if @video.sprite_image.attached?

    @video.probe! unless @video.probed?
    return unless @video.duration&.positive?

    Rails.logger.info("Generating sprite for #{@video.path}")

    movie = FFMPEG::Movie.new(@video.ffmpeg_input)
    interval = movie.duration / THUMB_COUNT

    Dir.mktmpdir("canister_sprite") do |tmpdir|
      sprite_path = File.join(tmpdir, "sprite.jpg")
      generate_sprite_sheet(movie, sprite_path, interval)

      thumb_height = detect_thumb_height(sprite_path)
      vtt_content = generate_vtt(interval, thumb_height)

      @video.sprite_image.attach(
        io: File.open(sprite_path),
        filename: "sprite_#{@video.id}.jpg",
        content_type: "image/jpeg"
      )

      @video.sprite_vtt.attach(
        io: StringIO.new(vtt_content),
        filename: "sprite_#{@video.id}.vtt",
        content_type: "text/vtt"
      )

      Rails.logger.info("Created sprite for #{@video.path}")
    end

    @video
  end

  private

  # Single ffmpeg command: extract frames at intervals and tile them into a grid.
  # No ImageMagick dependency — ffmpeg handles everything.
  def generate_sprite_sheet(movie, output_path, interval)
    ffmpeg_input = @video.ffmpeg_input
    input_arg = @video.local? ? Shellwords.escape(ffmpeg_input) : "\"#{ffmpeg_input}\""

    # fps=1/interval selects one frame per interval, scale sets thumb width,
    # tile assembles them into a COLUMNS x ROWS grid.
    cmd = "ffmpeg -v quiet -i #{input_arg}" \
          " -vf fps=1/#{interval},scale=#{THUMB_WIDTH}:-2,tile=#{COLUMNS}x#{ROWS}" \
          " -frames:v 1 -qscale:v 5" \
          " -y #{Shellwords.escape(output_path)}"
    raise "ffmpeg sprite generation failed: #{$?}" unless system(cmd)
  end

  # Derive thumb height from the sprite sheet dimensions.
  def detect_thumb_height(sprite_path)
    output = `ffprobe -v quiet -select_streams v:0 -show_entries stream=height -of csv=p=0 #{Shellwords.escape(sprite_path)} 2>/dev/null`.strip
    return 90 if output.empty?

    (output.to_i.to_f / ROWS).round
  end

  def generate_vtt(interval, thumb_height)
    lines = ["WEBVTT", ""]

    THUMB_COUNT.times do |i|
      start_time = i * interval
      end_time = (i + 1) * interval
      col = i % COLUMNS
      row = i / COLUMNS
      x = col * THUMB_WIDTH
      y = row * thumb_height

      lines << format_vtt_time(start_time) + " --> " + format_vtt_time(end_time)
      lines << "../sprite#xywh=#{x},#{y},#{THUMB_WIDTH},#{thumb_height}"
      lines << ""
    end

    lines.join("\n")
  end

  def format_vtt_time(seconds)
    hours = (seconds / 3600).to_i
    minutes = ((seconds % 3600) / 60).to_i
    secs = seconds % 60
    format("%02d:%02d:%06.3f", hours, minutes, secs)
  end
end
