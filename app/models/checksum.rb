class Checksum < ApplicationRecord
  belongs_to :hashable, polymorphic: true

  enum :checksum_type, {opensubtitles: "opensubtitles"}

  validates :hash_value, presence: true
end
