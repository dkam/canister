class CleanService
  def initialize
    @manager = MediaManager.instance
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
        unless Video.exists?(id: $1)
          @manager.info("Video #{$1} no longer exists")
          FileUtils.rm_r [File.join(dir, f)]
        end
      end
    }
  end

  def remove_deleted
    @manager.info("Removing metadata for deleted media")

    Video.all.each do |video|
      unless video.media_exists?
        @manager.info("Video #{video.path} no longer exists.")
        video.destroy
      end
    end
  end
end
