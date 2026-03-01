class Canister::Tasks::Export < Canister::Tasks::Base
  def start
    create_folders
    @mappings = {performers: [], studios: [], galleries: [], scenes: []}

    @manager.total = Scene.count + Gallery.count + Performer.count + Studio.count

    export_scenes
    export_galleries
    export_performers
    export_studios

    Canister::JSONUtility.save_mappings(json: @mappings)

    export_scraped

    nil
  end

  private

  def create_folders
    FileUtils.mkdir_p(Canister::STASH_SCENES_DIRECTORY) unless File.directory?(Canister::STASH_SCENES_DIRECTORY)
    FileUtils.mkdir_p(Canister::STASH_GALLERIES_DIRECTORY) unless File.directory?(Canister::STASH_GALLERIES_DIRECTORY)
    FileUtils.mkdir_p(Canister::STASH_PERFORMERS_DIRECTORY) unless File.directory?(Canister::STASH_PERFORMERS_DIRECTORY)
    FileUtils.mkdir_p(Canister::STASH_STUDIOS_DIRECTORY) unless File.directory?(Canister::STASH_STUDIOS_DIRECTORY)
  end

  def export_scenes
    Scene.all.each do |scene|
      @manager.current += 1
      @mappings[:scenes].push(id: scene.id, path: scene.path)

      json = {}
      json[:checksums] = scene.checksums.map { |c| {type: c.checksum_type, value: c.hash_value} }
      json[:title] = scene.title if scene.title
      json[:studio] = scene.studio.name if scene.studio && scene.studio.name
      json[:url] = scene.url if scene.url
      json[:date] = scene.date.to_s if scene.date
      json[:rating] = scene.rating if scene.rating
      json[:details] = scene.details if scene.details
      json[:gallery_id] = scene.gallery.id if scene.gallery
      json[:performers] = get_names(scene.performers) unless get_names(scene.performers).empty?
      json[:tags] = get_names(scene.tags) unless get_names(scene.tags).empty?

      if scene.scene_markers.count > 0
        json[:markers] = []
        scene.scene_markers.each { |marker|
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
      json[:file][:size] = scene.size
      json[:file][:duration] = scene.duration
      json[:file][:video_codec] = scene.video_codec
      json[:file][:audio_codec] = scene.audio_codec
      json[:file][:width] = scene.width
      json[:file][:height] = scene.height
      json[:file][:framerate] = scene.framerate
      json[:file][:bitrate] = scene.bitrate

      sceneJSON_path = File.join(Canister::STASH_SCENES_DIRECTORY, "#{scene.id}.json")

      existing_json = File.exist?(sceneJSON_path) ? JSON.parse(File.read(sceneJSON_path)) : nil
      next if existing_json == json.as_json

      Canister::JSONUtility.save_scene(id: scene.id, json: json)
    end
  end

  def export_performers
    clean_performers
    Performer.all.each do |performer|
      @manager.current += 1
      @mappings[:performers].push(id: performer.id, name: performer.name)

      json = {}
      json[:name] = performer.name if performer.name
      json[:url] = performer.url if performer.url
      json[:twitter] = performer.twitter if performer.twitter
      json[:instagram] = performer.instagram if performer.instagram
      json[:birthdate] = performer.birthdate if performer.birthdate
      json[:ethnicity] = performer.ethnicity if performer.ethnicity
      json[:country] = performer.country if performer.country
      json[:eye_color] = performer.eye_color if performer.eye_color
      json[:height] = performer.height if performer.height
      json[:measurements] = performer.measurements if performer.measurements
      json[:fake_tits] = performer.fake_tits if performer.fake_tits
      json[:career_length] = performer.career_length if performer.career_length
      json[:tattoos] = performer.tattoos if performer.tattoos
      json[:piercings] = performer.piercings if performer.piercings
      json[:aliases] = performer.aliases if performer.aliases
      json[:favorite] = performer.favorite
      json[:image] = Base64.encode64(performer.image)

      next if json.empty?

      performerJSON_path = File.join(Canister::STASH_PERFORMERS_DIRECTORY, "#{performer.id}.json")

      existing_json = File.exist?(performerJSON_path) ? JSON.parse(File.read(performerJSON_path)) : nil
      next if existing_json == json.as_json

      Canister::JSONUtility.save_performer(id: performer.id, json: json)
    end
  end

  def export_studios
    Studio.all.each do |studio|
      @manager.current += 1
      @mappings[:studios].push(id: studio.id, name: studio.name)

      json = {}
      json[:name] = studio.name if studio.name
      json[:url] = studio.url if studio.url
      json[:image] = Base64.encode64(studio.image)

      next if json.empty?

      studioJSON_path = File.join(Canister::STASH_STUDIOS_DIRECTORY, "#{studio.id}.json")

      existing_json = File.exist?(studioJSON_path) ? JSON.parse(File.read(studioJSON_path)) : nil
      next if existing_json == json.as_json

      Canister::JSONUtility.save_studio(id: studio.id, json: json)
    end
  end

  def export_galleries
    Gallery.all.each do |gallery|
      @manager.current += 1
      @mappings[:galleries].push(id: gallery.id, path: gallery.path)

      json = {}
      json[:title] = gallery.title if gallery.title
      json[:performers] = get_names(gallery.performers) unless get_names(gallery.performers).empty?

      next if json.empty?

      galleryJSON_path = File.join(Canister::STASH_GALLERIES_DIRECTORY, "#{gallery.id}.json")

      existing_json = File.exist?(galleryJSON_path) ? JSON.parse(File.read(galleryJSON_path)) : nil
      next if existing_json == json.as_json

      Canister::JSONUtility.save_gallery(id: gallery.id, json: json)
    end
  end

  def export_scraped
    results = []
    ScrapedItem.all.each do |scraped_item|
      json = {}

      json[:title] = scraped_item.title unless scraped_item.title.blank?
      json[:description] = scraped_item.description unless scraped_item.description.blank?
      json[:url] = scraped_item.url unless scraped_item.url.blank?
      json[:date] = scraped_item.date unless scraped_item.date.blank?
      json[:rating] = scraped_item.rating unless scraped_item.rating.blank?
      json[:tags] = scraped_item.tags unless scraped_item.tags.blank?
      json[:models] = scraped_item.models unless scraped_item.models.blank?
      json[:episode] = scraped_item.episode unless scraped_item.episode.blank?
      json[:gallery_filename] = scraped_item.gallery_filename unless scraped_item.gallery_filename.blank?
      json[:gallery_url] = scraped_item.gallery_url unless scraped_item.gallery_url.blank?
      json[:video_filename] = scraped_item.video_filename unless scraped_item.video_filename.blank?
      json[:video_url] = scraped_item.video_url unless scraped_item.video_url.blank?
      json[:studio] = scraped_item.studio.name
      json[:updated_at] = scraped_item.updated_at

      results.push(json)
    end
    Canister::JSONUtility.save_scraped(json: results)
  end

  def get_names(objects)
    return nil unless objects

    objects.each_with_object([]) { |object, names|
      unless object.name.nil?
        names << object.name
      end
    }
  end

  def clean_performers
    glob = File.join(Canister::STASH_PERFORMERS_DIRECTORY, "*.json")
    Dir[glob].each do |path|
      id = File.basename(path, ".json")
      next if Performer.find_by(id: id)

      @manager.info("Performer cleanup removing #{id}")
      File.delete(File.join(Canister::STASH_PERFORMERS_DIRECTORY, "#{id}.json"))
    end
  end
end
