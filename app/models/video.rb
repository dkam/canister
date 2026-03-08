class Video < ApplicationRecord
  include Filterable
  include SqliteSearch
  include Streamable
  include Taggable

  after_commit -> { broadcast_refresh_later_to(library) }, if: :library_id?

  search_scope :title, :details, :path

  validates :path, presence: true, uniqueness: true
  validates :checksums, presence: true

  has_and_belongs_to_many :people
  has_many :checksums, as: :hashable, dependent: :destroy
  has_one :gallery, as: :ownable, dependent: :nullify
  has_many :video_markers, -> { order(seconds: :asc) }, dependent: :destroy
  has_many :screenshots, dependent: :destroy
  has_one_attached :preview_clip
  belongs_to :library, optional: true, touch: true
  belongs_to :studio, optional: true, touch: true

  before_destroy :cleanup_hls_cache

  scoped_search on: [:title, :details, :path]
  scoped_search relation: :checksums, on: :hash_value
  scoped_search relation: :video_markers, on: :title

  scope :filter_studios, ->(studio_ids) { where studio_id: studio_ids }
  scope :filter_people, ->(person_ids) { joins(:people).where("people.id IN (?)", person_ids).distinct }

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
      joins(:video_markers).group("videos.id").having("count(video_id) > 0")
    else
      left_outer_joins(:video_markers).where(video_markers: {id: nil})
    end
  }
  scope :is_missing, ->(missing) {
    if missing.first == "gallery"
      missing_gallery
    elsif missing.first == "people"
      missing_people
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
      .group("videos.id")
      .having("count(taggings.tag_id) = #{tag_ids.length}")
      .distinct
  }
  scope :person_id, ->(person_id) { joins(:people).where("people.id = ?", person_id).distinct }

  scope :missing_gallery, -> { joins("LEFT OUTER JOIN galleries ON galleries.ownable_id = videos.id").where("galleries.ownable_id IS NULL") }
  scope :missing_people, -> { left_outer_joins(:people).where(people: {id: nil}) }
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
    File.exist?(transcode_path) ? transcode_path : absolute_path
  end

  def media_exists?
    library ? backend.file_exists?(path) : File.exist?(path)
  end

  def ffmpeg_input
    return path unless library
    backend.ffmpeg_input(path)
  end

  def absolute_path
    return path unless library
    backend.absolute_path(path)
  end

  def backend
    library&.backend
  end

  def local?
    library.nil? || library.local?
  end

  def remote?
    library&.remote? || false
  end

  def transcode_path
    File.join(Canister::TRANSCODE_DIRECTORY, "#{id}.mp4")
  end

  def screenshot(seconds: nil, width: nil)
    cache_key = "video_#{id}"
    if seconds
      cache_key += "_#{seconds}"
    end
    if width
      cache_key += "_#{width}"
    end

    if Rails.cache.read(cache_key).nil?
      data = Canister::Movie.screenshot(path: ffmpeg_input, seconds: seconds, width: width)
      Rails.cache.write(cache_key, data)
      data
    else
      Rails.cache.read(cache_key)
    end
  end

  def chapter_vtt
    vtt = ["WEBVTT", ""]
    video_markers.each do |marker|
      end_time = marker.end_seconds.present? ? marker.end_seconds : marker.seconds
      vtt.push("#{get_vtt_time(marker.seconds)} --> #{get_vtt_time(end_time)}")
      vtt.push(marker.title)
      vtt.push("")
    end

    vtt.join("\n")
  end

  def probed?
    duration.present?
  end

  def probe!
    return if probed?

    metadata = ProbeVideoJob.ffprobe(ffmpeg_input)
    update!(
      size: metadata[:size] || (backend ? backend.file_size(path) : File.size(ffmpeg_input)),
      duration: metadata[:duration],
      video_codec: metadata[:video_codec],
      audio_codec: metadata[:audio_codec],
      width: metadata[:width],
      height: metadata[:height],
      framerate: metadata[:framerate],
      bitrate: metadata[:bitrate]
    )
  end

  def primary_checksum
    checksums.find_by(checksum_type: :opensubtitles) || checksums.first
  end

  def checksum
    checksum_value(type: :opensubtitles)
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

  def cleanup_hls_cache
    hls_dir = Rails.root.join("tmp", "hls", id.to_s)
    FileUtils.rm_rf(hls_dir) if hls_dir.exist?
  end
end
