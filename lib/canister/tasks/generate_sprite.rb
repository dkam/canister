class Canister::Tasks::GenerateSprite < Canister::Tasks::Base
  def initialize(scene:)
    super()
    @scene = scene
  end

  def start
    return unless !sprite_exists?
    create_folders

    movie = Canister::Movie::VTTGenerator.new(
      path: @scene.path,
      sprite_filename: sprite_filename,
      vtt_filename: vtt_filename,
      output_directory: Canister::STASH_VTT_DIRECTORY
    )
    movie.generate

    return @scene
  end

  private

    def create_folders
      FileUtils.mkdir_p(Canister::STASH_VTT_DIRECTORY) unless File.directory?(Canister::STASH_VTT_DIRECTORY)
      tmp_dir = File.join(Canister::STASH_VTT_DIRECTORY, 'tmp')
      FileUtils.mkdir_p(tmp_dir) unless File.directory?(tmp_dir)
    end

    def sprite_exists?
      sprite_path = File.join(Canister::STASH_VTT_DIRECTORY, sprite_filename)
      vtt_path = File.join(Canister::STASH_VTT_DIRECTORY, vtt_filename)
      File.exist?(sprite_path) && File.exist?(vtt_path)
    end

    def sprite_filename
      "#{@scene.checksum}_sprite.jpg"
    end

    def vtt_filename
      "#{@scene.checksum}_thumbs.vtt"
    end
end
