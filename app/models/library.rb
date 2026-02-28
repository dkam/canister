class Library < ApplicationRecord
  has_many :scenes

  enum :kind, { local: 'local', http: 'http', webdav: 'webdav', s3: 's3',
                jellyfin: 'jellyfin', plex: 'plex', dlna: 'dlna' }, prefix: true
  enum :default_video_kind, { video: 'video', music_video: 'music_video' }

  validates :name, presence: true
  validates :path, presence: true
end
