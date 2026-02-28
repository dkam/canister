class Canister::Tasks::GeneratePreview < Canister::Tasks::Base
  def initialize(scene:)
    super()
    @scene = scene
  end

  def start
    return unless !preview_exists?
    create_folders

    movie = Canister::Movie::PreviewGenerator.new(
      path: @scene.path,
      video_filename: video_filename,
      image_filename: image_filename,
      output_directory: Canister::STASH_SCREENSHOTS_DIRECTORY
    )
    movie.generate

    return @scene
  end

  private

    def create_folders
      FileUtils.mkdir_p(Canister::STASH_SCREENSHOTS_DIRECTORY) unless File.directory?(Canister::STASH_SCREENSHOTS_DIRECTORY)
      tmp_dir = File.join(Canister::STASH_SCREENSHOTS_DIRECTORY, 'tmp')
      FileUtils.mkdir_p(tmp_dir) unless File.directory?(tmp_dir)
    end

    def preview_exists?
      File.exist?(File.join(Canister::STASH_SCREENSHOTS_DIRECTORY, video_filename)) &&
      File.exist?(File.join(Canister::STASH_SCREENSHOTS_DIRECTORY, image_filename))
    end

    def video_filename
      "#{@scene.checksum}.mp4"
    end

    def image_filename
      "#{@scene.checksum}.webp"
    end
end
