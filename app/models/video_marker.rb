class VideoMarker < ApplicationRecord
  include Filterable
  include Taggable

  belongs_to :primary_tag, class_name: "Tag"

  belongs_to :video, touch: true

  scoped_search on: [:title, :video_id]
  scoped_search relation: :video, on: :title
  # scoped_search relation: :primary_tag, on: :name
  # scoped_search relation: :tags, on: :name

  validates :title, presence: true
  validates :seconds, numericality: true
  validates :end_seconds, numericality: {greater_than: :seconds}, allow_nil: true

  def self.tag_id(tag_id)
    tag_id = tag_id.first if tag_id.is_a? Array

    VideoMarker.left_outer_joins(:tags)
      .where("'video_markers'.'primary_tag_id' = :tag_id OR 'tags'.'id' = :tag_id", tag_id: tag_id)
      .distinct
  end

  scope :tags, ->(tag_ids) {
    tag_ids = tag_ids.uniq

    markers = left_outer_joins(:tags)
      .where(video_markers: {primary_tag_id: tag_ids})
      .distinct

    ids = []
    if markers.count == 0
      return left_outer_joins(:tags)
          .where(tags: {id: tag_ids})
          .group("video_markers.id")
          .having("count(taggings.tag_id) = #{tag_ids.length}")
          .distinct
    else
      ids += left_outer_joins(:tags)
        .where(tags: {id: tag_ids})
        .group("video_markers.id")
        .having("count(taggings.tag_id) = #{tag_ids.length}")
        .distinct
        .pluck(:id)
    end

    markers.each { |marker|
      difference = tag_ids - [marker.primary_tag_id]
      difference -= marker.tags.pluck(:id)

      ids << marker.id if difference.length == 0
    }

    where(id: ids.uniq)
  }

  scope :video_tags, ->(video_tag_ids) {
    tag_ids = video_tag_ids.uniq

    left_outer_joins(video: [:tags])
      .where(video: {taggings: {tag_id: tag_ids}})
      .group("video_markers.id")
      .having("count(taggings.tag_id) = #{video_tag_ids.length}")
      .distinct
  }

  scope :marker_and_video_tags, ->(marker_tag_ids, video_tag_ids) {
    video_tag_ids = video_tag_ids.uniq
    marker_tag_ids = marker_tag_ids.uniq

    video = video_tags(video_tag_ids)
    marker = tags(marker_tag_ids)

    ids = marker.pluck(:id) & video.pluck(:id)
    where(id: ids.uniq)
  }

  scope :people, ->(video_person_ids) {
    person_ids = video_person_ids.uniq

    left_outer_joins(video: [:people])
      .where(video: {people: {id: person_ids}})
      .distinct
  }

  def stream_file_path
    File.join(Canister::STASH_MARKERS_DIRECTORY, video.checksum, "#{seconds.to_i}.mp4")
  end

  def stream_preview_path
    File.join(Canister::STASH_MARKERS_DIRECTORY, video.checksum, "#{seconds.to_i}.webp")
  end
end
