class ScrapedItem < ApplicationRecord
  belongs_to :studio

  validates :title, :url, :date, :video_filename, presence: true

  def video
    videos = Video.where("path like ?", "%/#{video_filename}").select { |video| video.studio.nil? || video.studio.id == studio.id }
    if videos.count == 1
      videos.first
    elsif videos.count > 1
      videos = Video.where("path like ?", "%#{studio.name}%/#{video_filename}")
      videos.first if videos.count == 1
    end
  end

  def gallery
    return nil if video.nil? || gallery_filename.blank?
    video_path = File.dirname(video.path)
    gallery_path = File.join(video_path, gallery_filename)
    Gallery.find_by(path: gallery_path)
  end

  def populate_video(the_video = nil)
    the_video = video if the_video.nil?
    return if the_video.nil?

    details = ""
    valid_tags = []
    valid_people = []
    if !description.blank?
      details += "#{description}\n\n"
    end
    if !rating.blank?
      details += "Rating: #{rating}\n"
    end
    if !tags.blank?
      details += "Tags: #{tags}\n"
      valid_tags = tags.split(", ").map { |tag|
        next if tag.strip.titleize == "Sexy"
        Tag.where(name: tag.strip.titleize).first
      }.compact
    end
    if !models.blank?
      details += "Models: #{models}"
      model_names = models.split(", ")
      model_objects = model_names.map { |model_name| Person.where(name: model_name.strip.titleize).first }.compact
      valid_people = model_objects if model_objects.count == model_names.count
    end

    the_video.title = if title.include?("-")
      title
    else
      title.titleize
    end
    the_video.url = url
    the_video.date = date
    the_video.tags = valid_tags unless the_video.tags.count > 0
    the_video.people = valid_people unless the_video.people.count > 0
    the_video.details = details
    the_video.gallery = gallery
    the_video.studio = studio

    the_video.save
  end
end
