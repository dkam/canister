class GeneratePreviewService
  CHUNK_COUNT = 12
  CHUNK_DURATION = 0.75
  WIDTH = 640

  def initialize(video:)
    @manager = MediaManager.instance
    @video = video
  end

  def start
    return if @video.preview_clip.attached?

    @manager.info("Generating preview for #{@video.path}")

    movie = FFMPEG::Movie.new(@video.ffmpeg_input)

    Dir.mktmpdir("canister_preview") do |tmpdir|
      chunk_paths = generate_chunks(movie, tmpdir)
      concat_path = write_concat_file(tmpdir, chunk_paths)
      output_path = File.join(tmpdir, "preview.mp4")

      concatenate_chunks(concat_path, output_path)

      @video.preview_clip.attach(
        io: File.open(output_path),
        filename: "preview_#{@video.id}.mp4",
        content_type: "video/mp4"
      )

      @manager.info("Created preview for #{@video.path}")
    end

    @video
  end

  private

  def generate_chunks(movie, tmpdir)
    step = movie.duration / CHUNK_COUNT
    ffmpeg_input = @video.ffmpeg_input
    CHUNK_COUNT.times.map do |i|
      chunk_path = File.join(tmpdir, "chunk_#{i.to_s.rjust(3, "0")}.mp4")
      input_arg = @video.local? ? Shellwords.escape(ffmpeg_input) : "\"#{ffmpeg_input}\""
      cmd = "ffmpeg -v quiet -ss #{i * step} -t #{CHUNK_DURATION} -i #{input_arg}" \
            " -y -c:v libx264 -profile:v high -level 4.2 -preset medium -crf 21" \
            " -vsync 2 -threads 4 -vf scale=#{WIDTH}:-2 -an" \
            " -movflags +faststart #{Shellwords.escape(chunk_path)}"
      system(cmd)
      chunk_path
    end
  end

  def write_concat_file(tmpdir, chunk_paths)
    concat_path = File.join(tmpdir, "files.txt")
    File.write(concat_path, chunk_paths.map { |p| "file '#{p}'" }.join("\n"))
    concat_path
  end

  def concatenate_chunks(concat_path, output_path)
    cmd = "ffmpeg -v quiet -f concat -safe 0 -i #{Shellwords.escape(concat_path)}" \
          " -y -c copy #{Shellwords.escape(output_path)}"
    raise "ffmpeg preview concat failed: #{$?}" unless system(cmd)
  end
end
