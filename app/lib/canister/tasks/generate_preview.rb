class Canister::Tasks::GeneratePreview < Canister::Tasks::Base
  CHUNK_COUNT = 12
  CHUNK_DURATION = 0.75
  WIDTH = 640

  def initialize(scene:)
    super()
    @scene = scene
  end

  def start
    return if @scene.preview_clip.attached?

    @manager = Canister::Manager.instance
    @manager.info("Generating preview for #{@scene.path}")

    video = FFMPEG::Movie.new(@scene.path)

    Dir.mktmpdir("canister_preview") do |tmpdir|
      chunk_paths = generate_chunks(video, tmpdir)
      concat_path = write_concat_file(tmpdir, chunk_paths)
      output_path = File.join(tmpdir, "preview.mp4")

      concatenate_chunks(concat_path, output_path)

      @scene.preview_clip.attach(
        io: File.open(output_path),
        filename: "preview_#{@scene.id}.mp4",
        content_type: "video/mp4"
      )

      @manager.info("Created preview for #{@scene.path}")
    end

    @scene
  end

  private

  def generate_chunks(video, tmpdir)
    step = video.duration / CHUNK_COUNT
    CHUNK_COUNT.times.map do |i|
      chunk_path = File.join(tmpdir, "chunk_#{i.to_s.rjust(3, "0")}.mp4")
      cmd = "ffmpeg -v quiet -ss #{i * step} -t #{CHUNK_DURATION} -i #{Shellwords.escape(@scene.path)}" \
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
