class Scene < ApplicationRecord
  include Filterable
  include Streamable
  include Taggable

  validates :path, presence: true, uniqueness: true
  validates :checksums, presence: true

  has_and_belongs_to_many :performers
  has_many :checksums, as: :hashable, dependent: :destroy
  has_one :gallery, as: :ownable, dependent: :nullify
  has_many :scene_markers, dependent: :destroy
  has_many :screenshots, dependent: :destroy
  has_one_attached :preview_clip
  belongs_to :library, optional: true
  belongs_to :studio, optional: true, touch: true

  scoped_search on: [:title, :details, :path]
  scoped_search relation: :checksums, on: :hash_value
  scoped_search relation: :scene_markers, on: :title

  default_scope { order(path: :asc) }
  scope :filter_studios, ->(studio_ids) { where studio_id: studio_ids }
  scope :filter_performers, ->(performer_ids) { joins(:performers).where("performers.id IN (?)", performer_ids).distinct }

  scope :rating, ->(rating) { where("rating = ?", rating) }
  scope :resolution, ->(resolution) {
    resolution = resolution.first if resolution.is_a?(Array)
    if resolution == "240p"
      where("height >= 240 AND height < 480")
    elsif resolution == "480p"
      where("height >= 480 AND height < 720")
    elsif resolution == "720p"
      where("height >= 720 AND height < 1080")
    elsif resolution == "1080p"
      where("height >= 1080 AND height < 2160")
    elsif resolution == "4k"
      where("height >= 2160")
    else
      where("height < 240")
    end
  }
  scope :has_markers, ->(has_markers) {
    has_markers = has_markers.first if has_markers.is_a?(Array)
    if has_markers == "true"
      joins(:scene_markers).group("scenes.id").having("count(scene_id) > 0")
    else
      left_outer_joins(:scene_markers).where(scene_markers: {id: nil})
    end
  }
  scope :is_missing, ->(missing) {
    if missing.first == "gallery"
      missing_gallery
    elsif missing.first == "performers"
      missing_performers
    else
      where missing.first.to_sym => nil
    end
  }
  scope :studio_id, ->(studio_id) { where studio_id: studio_id }
  scope :tag_id, ->(tag_id) { joins(:tags).where("tags.id = ?", tag_id).distinct }
  scope :tags, ->(tag_ids) {
    tag_ids = tag_ids.uniq

    joins(:tags)
      .where(tags: {id: tag_ids})
      .group("scenes.id")
      .having("count(taggings.tag_id) = #{tag_ids.length}")
      .distinct
  }
  scope :performer_id, ->(performer_id) { joins(:performers).where("performers.id = ?", performer_id).distinct }

  scope :missing_gallery, -> { joins("LEFT OUTER JOIN galleries ON galleries.ownable_id = scenes.id").where("galleries.ownable_id IS NULL") }
  scope :missing_performers, -> { left_outer_joins(:performers).where(performers: {id: nil}) }
  scope :needing_processing, -> {
    where.not(video_codec: Canister::VALID_HTML5_CODECS)
  }

  def needs_remux?
    !File.exist?(transcode_path) &&
      Canister::VALID_HTML5_CODECS.include?(video_codec) &&
      !Canister::STREAMABLE_EXTENSIONS.include?(File.extname(path).downcase)
  end

  def needs_transcode?
    !File.exist?(transcode_path) &&
      !Canister::VALID_HTML5_CODECS.include?(video_codec)
  end

  def is_streamable
    return true if File.exist?(transcode_path)
    Canister::VALID_HTML5_CODECS.include?(video_codec)
  end

  def stream_file_path
    File.exist?(transcode_path) ? transcode_path : path
  end

  def media_exists?
    File.exist?(path)
  end

  def transcode_path
    File.join(Canister::TRANSCODE_DIRECTORY, "#{id}.mp4")
  end

  def screenshot(seconds: nil, width: nil)
    cache_key = "scene_#{id}"
    if seconds
      cache_key += "_#{seconds}"
    end
    if width
      cache_key += "_#{width}"
    end

    if Rails.cache.read(cache_key).nil?
      data = Canister::Movie.screenshot(path: path, seconds: seconds, width: width)
      Rails.cache.write(cache_key, data)
      data
    else
      Rails.cache.read(cache_key)
    end
  end

  def chapter_vtt
    vtt = ["WEBVTT", ""]
    scene_markers.each do |scene_marker|
      end_time = scene_marker.end_seconds.present? ? scene_marker.end_seconds : scene_marker.seconds
      vtt.push("#{get_vtt_time(scene_marker.seconds)} --> #{get_vtt_time(end_time)}")
      vtt.push(scene_marker.title)
      vtt.push("")
    end

    vtt.join("\n")
  end

  def primary_checksum
    checksums.find_by(checksum_type: :opensubtitles) || checksums.first
  end

  def checksum_value(type: :opensubtitles)
    checksums.find_by(checksum_type: type)&.hash_value
  end

  def checksums_by_type
    checksums.group_by(&:checksum_type)
  end

  private

  def get_vtt_time(seconds)
    Time.at(seconds).gmtime.strftime("%H:%M:%S")
  end

  def get_vtt_time(seconds)
    Time.at(seconds).gmtime.strftime("%H:%M:%S")
  end
end
