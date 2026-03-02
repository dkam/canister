class Library < ApplicationRecord
  has_many :scenes, dependent: :nullify

  enum :kind, {local: "local", http: "http", webdav: "webdav", s3: "s3",
                jellyfin: "jellyfin", plex: "plex", dlna: "dlna"}, prefix: true
  enum :default_video_kind, {video: "video", music_video: "music_video"}

  validates :name, presence: true
  validates :path, presence: true

  def backend
    @backend ||= case kind
    when "local" then Library::LocalBackend.new(self)
    when "webdav" then Library::WebdavBackend.new(self)
    else
      raise "Unsupported library kind: #{kind}"
    end
  end

  def scan
    ScanJob.perform_later(id)
  end

  def scan_now
    paths = backend.list_files(extensions: Canister::MEDIA_EXTENSIONS)
    puts "Scanning #{paths.size} files in #{name} (#{path})..."
    errors = []
    paths.each_with_index do |relative_path, i|
      print "\r[#{i + 1}/#{paths.size}] #{relative_path}"
      Canister::Tasks::Scan.new(path: relative_path, library: self).start
    rescue => e
      errors << { path: relative_path, error: e.message }
      puts "\n  ERROR: #{e.message}"
    end
    puts "\nDone. #{paths.size - errors.size} succeeded, #{errors.size} errors."
  end

  def local?
    kind == "local"
  end

  def remote?
    !local?
  end
end
