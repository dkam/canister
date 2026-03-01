class Checksum < ApplicationRecord
  belongs_to :hashable, polymorphic: true

  enum :checksum_type, {md5: "md5", xxhash: "xxhash", opensubtitles: "opensubtitles"}

  validates :hash_value, presence: true
end
