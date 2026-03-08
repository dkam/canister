class CleanService
  def initialize
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
    Rails.logger.info("Cleaning #{dir}")

    Dir.foreach(dir) { |f|
      if /([a-z0-9]{25})/ =~ f
        unless Video.exists?(id: $1)
          Rails.logger.info("Video #{$1} no longer exists")
          FileUtils.rm_r [File.join(dir, f)]
        end
      end
    }
  end

  def remove_deleted
    Rails.logger.info("Removing metadata for deleted media")

    Video.all.each do |video|
      unless video.media_exists?
        Rails.logger.info("Video #{video.path} no longer exists.")
        video.destroy
      end
    end
  end
end
