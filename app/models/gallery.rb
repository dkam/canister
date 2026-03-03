class Gallery < ApplicationRecord
  has_and_belongs_to_many :performers
  has_many :checksums, as: :hashable, dependent: :destroy
  validates :checksums, presence: true
  belongs_to :ownable, polymorphic: true, optional: true

  scoped_search on: [:title, :path]

  def primary_checksum
    checksums.first
  end

  def checksum
    checksum_value
  end

  def checksum_value(type: :opensubtitles)
    checksums.find_by(checksum_type: type)&.hash_value
  end

  def checksums_by_type
    checksums.group_by(&:checksum_type)
  end

  scope :unowned, -> { where ownable_id: nil }
  scope :unowned_in_path, ->(path) { unowned.where("path like ?", "%#{path}%") }

  def files
    Canister::ZipUtility.get_files(path)
  end
end
