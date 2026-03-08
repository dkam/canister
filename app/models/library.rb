class Library < ApplicationRecord
  broadcasts_refreshes

  has_many :videos, dependent: :destroy

  enum :kind, {local: "local", http: "http", webdav: "webdav", s3: "s3",
                jellyfin: "jellyfin", plex: "plex", dlna: "dlna"}, prefix: true
  enum :default_video_kind, {video: "video", music_video: "music_video"}

  validates :name, presence: true
  validates :path, presence: true, uniqueness: true

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

  def local?
    kind == "local"
  end

  def remote?
    !local?
  end
end
