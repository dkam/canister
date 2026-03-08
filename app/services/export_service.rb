class ExportService
  def initialize
  end

  def start
    create_folders
    @mappings = {people: [], studios: [], galleries: [], videos: []}

    export_videos
    export_galleries
    export_people
    export_studios

    JsonUtility.save_mappings(json: @mappings)

    nil
  end

  private

  def create_folders
    FileUtils.mkdir_p(Canister::STASH_VIDEOS_DIRECTORY) unless File.directory?(Canister::STASH_VIDEOS_DIRECTORY)
    FileUtils.mkdir_p(Canister::STASH_GALLERIES_DIRECTORY) unless File.directory?(Canister::STASH_GALLERIES_DIRECTORY)
    FileUtils.mkdir_p(Canister::STASH_PEOPLE_DIRECTORY) unless File.directory?(Canister::STASH_PEOPLE_DIRECTORY)
    FileUtils.mkdir_p(Canister::STASH_STUDIOS_DIRECTORY) unless File.directory?(Canister::STASH_STUDIOS_DIRECTORY)
  end

  def export_videos
    Video.all.each do |video|
      @mappings[:videos].push(id: video.id, path: video.path)

      json = {}
      json[:checksums] = video.checksums.map { |c| {type: c.checksum_type, value: c.hash_value} }
      json[:title] = video.title if video.title
      json[:studio] = video.studio.name if video.studio && video.studio.name
      json[:url] = video.url if video.url
      json[:date] = video.date.to_s if video.date
      json[:rating] = video.rating if video.rating
      json[:details] = video.details if video.details
      json[:gallery_id] = video.gallery.id if video.gallery
      json[:people] = get_names(video.people) unless get_names(video.people).empty?
      json[:tags] = get_names(video.tags) unless get_names(video.tags).empty?

      if video.video_markers.count > 0
        json[:markers] = []
        video.video_markers.each { |marker|
          marker_json = {
            id: marker.id,
            title: marker.title,
            seconds: marker.seconds,
            primary_tag: marker.primary_tag.name,
            tags: get_names(marker.tags)
          }
          marker_json[:end_seconds] = marker.end_seconds if marker.end_seconds.present?
          json[:markers].push(marker_json)
        }
      elsif !json[:markers].nil?
        json.delete(:markers)
      end

      json[:file] = {}
      json[:file][:size] = video.size
      json[:file][:duration] = video.duration
      json[:file][:video_codec] = video.video_codec
      json[:file][:audio_codec] = video.audio_codec
      json[:file][:width] = video.width
      json[:file][:height] = video.height
      json[:file][:framerate] = video.framerate
      json[:file][:bitrate] = video.bitrate

      videoJSON_path = File.join(Canister::STASH_VIDEOS_DIRECTORY, "#{video.id}.json")

      existing_json = File.exist?(videoJSON_path) ? JSON.parse(File.read(videoJSON_path)) : nil
      next if existing_json == json.as_json

      JsonUtility.save_video(id: video.id, json: json)
    end
  end

  def export_people
    clean_people
    Person.all.each do |person|
      @mappings[:people].push(id: person.id, name: person.name)

      json = {}
      json[:name] = person.name if person.name
      json[:url] = person.url if person.url
      json[:twitter] = person.twitter if person.twitter
      json[:instagram] = person.instagram if person.instagram
      json[:birthdate] = person.birthdate if person.birthdate
      json[:ethnicity] = person.ethnicity if person.ethnicity
      json[:country] = person.country if person.country
      json[:eye_color] = person.eye_color if person.eye_color
      json[:height] = person.height if person.height
      json[:measurements] = person.measurements if person.measurements
      json[:fake_tits] = person.fake_tits if person.fake_tits
      json[:career_length] = person.career_length if person.career_length
      json[:tattoos] = person.tattoos if person.tattoos
      json[:piercings] = person.piercings if person.piercings
      json[:aliases] = person.aliases if person.aliases
      json[:favorite] = person.favorite
      json[:image] = Base64.encode64(person.image.download) if person.image.attached?

      next if json.empty?

      personJSON_path = File.join(Canister::STASH_PEOPLE_DIRECTORY, "#{person.id}.json")

      existing_json = File.exist?(personJSON_path) ? JSON.parse(File.read(personJSON_path)) : nil
      next if existing_json == json.as_json

      JsonUtility.save_person(id: person.id, json: json)
    end
  end

  def export_studios
    Studio.all.each do |studio|
      @mappings[:studios].push(id: studio.id, name: studio.name)

      json = {}
      json[:name] = studio.name if studio.name
      json[:url] = studio.url if studio.url
      json[:image] = Base64.encode64(studio.image.download) if studio.image.attached?

      next if json.empty?

      studioJSON_path = File.join(Canister::STASH_STUDIOS_DIRECTORY, "#{studio.id}.json")

      existing_json = File.exist?(studioJSON_path) ? JSON.parse(File.read(studioJSON_path)) : nil
      next if existing_json == json.as_json

      JsonUtility.save_studio(id: studio.id, json: json)
    end
  end

  def export_galleries
    Gallery.all.each do |gallery|
      @mappings[:galleries].push(id: gallery.id, path: gallery.path)

      json = {}
      json[:title] = gallery.title if gallery.title
      json[:people] = get_names(gallery.people) unless get_names(gallery.people).empty?

      next if json.empty?

      galleryJSON_path = File.join(Canister::STASH_GALLERIES_DIRECTORY, "#{gallery.id}.json")

      existing_json = File.exist?(galleryJSON_path) ? JSON.parse(File.read(galleryJSON_path)) : nil
      next if existing_json == json.as_json

      JsonUtility.save_gallery(id: gallery.id, json: json)
    end
  end

  def get_names(objects)
    return nil unless objects

    objects.each_with_object([]) { |object, names|
      unless object.name.nil?
        names << object.name
      end
    }
  end

  def clean_people
    glob = File.join(Canister::STASH_PEOPLE_DIRECTORY, "*.json")
    Dir[glob].each do |path|
      id = File.basename(path, ".json")
      next if Person.find_by(id: id)

      Rails.logger.info("Person cleanup removing #{id}")
      File.delete(File.join(Canister::STASH_PEOPLE_DIRECTORY, "#{id}.json"))
    end
  end
end
