class Canister::Tasks::Clean < Canister::Tasks::Base
  def initialize
    super
  end

  def start
    remove_deleted
    clean_directory(Canister::STASH_SCREENSHOTS_DIRECTORY)
    clean_directory(Canister::STASH_VTT_DIRECTORY)
    clean_directory(Canister::STASH_TRANSCODE_DIRECTORY)
    nil
  end

  private

  def clean_directory(dir)
    @manager.info("Cleaning #{dir}")

    Dir.foreach(dir) { |f|
      if /([a-z0-9]{25})/ =~ f
        unless Scene.exists?(id: $1)
          @manager.info("Scene #{$1} no longer exists")
          FileUtils.rm_r [File.join(dir, f)]
        end
      end
    }
  end

  def remove_deleted
    @manager.info("Removing metadata for deleted media")

    Scene.all.each do |scene|
      unless scene.media_exists?
        @manager.info("Scene #{scene.path} no longer exists.")
        scene.destroy
      end
    end
  end
end
