class ImportService
  def initialize
    @manager = MediaManager.instance
  end

  def start
    @mappings = JsonUtility.mappings
    return unless @mappings

    import_people
    import_studios
    import_galleries
    import_tags

    ScrapedItem.transaction {
      import_scraped_sites
    }

    Video.transaction {
      import_videos
    }
  end

  private

  def import_scraped_sites
    scraped = JsonUtility.scraped
    return unless scraped

    scraped.each.with_index(1) { |json, index|
      @manager.info("Reading scraped site #{index} of #{scraped.count}\r")

      scraped_item = ScrapedItem.new

      scraped_item.title = json["title"]
      scraped_item.description = json["description"]
      scraped_item.url = json["url"]
      scraped_item.date = json["date"]
      scraped_item.rating = json["rating"]
      scraped_item.tags = json["tags"]
      scraped_item.models = json["models"]
      scraped_item.episode = json["episode"]
      scraped_item.gallery_filename = json["gallery_filename"]
      scraped_item.gallery_url = json["gallery_url"]
      scraped_item.video_filename = json["video_filename"]
      scraped_item.video_url = json["video_url"]

      studio = get_studio(json["studio"])
      scraped_item.studio = studio if studio

      scraped_item.save!
      scraped_item.touch(:updated_at, time: Time.parse(json["updated_at"]))
    }

    @manager.info("Scraped site import complete")
  end

  def import_people
    people = []
    images = {}

    @mappings["people"].each.with_index(1) { |personJSON, index|
      id = personJSON["id"]
      name = personJSON["name"]
      json = JsonUtility.person id
      next unless id && name && json

      @manager.info("Reading person #{index} of #{@mappings["people"].count}\r")

      person = Person.new(id: id)
      person.name = name
      person.url = json["url"]
      person.twitter = json["twitter"]
      person.instagram = json["instagram"]
      person.birthdate = json["birthdate"]
      person.ethnicity = json["ethnicity"]
      person.country = json["country"]
      person.eye_color = json["eye_color"]
      person.height = json["height"]
      person.measurements = json["measurements"]
      person.fake_tits = json["fake_tits"]
      person.career_length = json["career_length"]
      person.tattoos = json["tattoos"]
      person.piercings = json["piercings"]
      person.aliases = json["aliases"]
      person.favorite = json["favorite"]

      images[id] = json["image"] if json["image"].present?
      people.push(person)
    }

    @manager.info("Importing people...")
    Person.import(people, validate: false)

    @manager.info("Attaching person images...")
    images.each do |id, base64_data|
      person = Person.find_by(id: id)
      next unless person

      decoded = Base64.decode64(base64_data)
      mime_type = detect_mime(decoded)
      extension = mime_type.split("/").last

      person.image.attach(
        io: StringIO.new(decoded),
        filename: "person_#{id}.#{extension}",
        content_type: mime_type
      )
    end

    @manager.info("Person import complete")
  end

  def import_studios
    return unless @mappings["studios"]

    studios = []
    images = {}

    @mappings["studios"].each.with_index(1) { |studioJSON, index|
      id = studioJSON["id"]
      name = studioJSON["name"]
      json = JsonUtility.studio id
      next unless id && name && json

      @manager.info("Reading studio #{index} of #{@mappings["studios"].count}\r")

      studio = Studio.new(id: id)
      studio.name = name
      studio.url = json["url"]

      images[id] = json["image"] if json["image"].present?
      studios.push(studio)
    }

    @manager.info("Importing studios...")
    Studio.import(studios, validate: false)

    @manager.info("Attaching studio images...")
    images.each do |id, base64_data|
      studio = Studio.find_by(id: id)
      next unless studio

      decoded = Base64.decode64(base64_data)
      mime_type = detect_mime(decoded)
      extension = mime_type.split("/").last

      studio.image.attach(
        io: StringIO.new(decoded),
        filename: "studio_#{id}.#{extension}",
        content_type: mime_type
      )
    end

    @manager.info("Studio import complete")
  end

  def import_galleries
    galleries = []
    @mappings["galleries"].each.with_index(1) { |galleryJSON, index|
      id = galleryJSON["id"]
      path = galleryJSON["path"]
      next unless id && path

      @manager.info("Reading gallery #{index} of #{@mappings["galleries"].count}\r")

      gallery = Gallery.new(id: id)
      gallery.path = path

      json = JsonUtility.gallery id
      if json
        gallery.title = json["title"]

        people = get_people(json["people"])
        if people
          gallery.people = people
        end
      end

      galleries.push(gallery)
    }

    @manager.info("Importing galleries...")
    Gallery.import(galleries)
    @manager.info("Gallery import complete")
  end

  def import_tags
    tag_names = []
    tags = []

    @mappings["videos"].each.with_index(1) { |videoJSON, index|
      id = videoJSON["id"]
      path = videoJSON["path"]
      unless id && path
        @manager.warn("Video mapping without id and path! #{videoJSON}")
        next
      end

      @manager.info("Importing tags for video #{index} of #{@mappings["videos"].count}\r")

      json = JsonUtility.video id
      if json
        video_tag_names = json["tags"]
        if video_tag_names
          tag_names += video_tag_names
        end

        markers = json["markers"]
        if markers
          markers.each { |marker|
            primary_tag_name = marker["primary_tag"]
            if primary_tag_name
              tag_names.push(primary_tag_name)
            end

            video_marker_tag_names = marker["tags"]
            if video_marker_tag_names
              tag_names += video_marker_tag_names
            end
          }
        end
      end
    }

    tag_names.uniq!

    tag_names.each { |tag_name|
      tag = Tag.new(name: tag_name)
      tags.push(tag)
    }

    @manager.info("Importing tags...")
    Tag.import(tags)
    @manager.info("Tag import complete")
  end

  def import_videos
    @mappings["videos"].each.with_index(1) { |videoJSON, index|
      id = videoJSON["id"]
      path = videoJSON["path"]
      unless id && path
        @manager.warn("Video mapping without id and path! #{videoJSON}")
        next
      end

      @manager.info("Importing video #{index} of #{@mappings["videos"].count}\r")

      video = Video.find_by(id: id)
      video ||= Video.new(id: id)
      video.path = path

      json = JsonUtility.video id
      if json
        video.title = json["title"]
        video.details = json["details"]
        video.url = json["url"]
        video.date = json["date"]
        video.rating = json["rating"]

        studio = get_studio(json["studio"])
        video.studio = studio if studio

        gallery_id = json["gallery_id"]
        if gallery_id
          gallery = Gallery.find_by(id: gallery_id)
          if gallery
            video.gallery = gallery
          else
            @manager.warn("Gallery does not exist! #{gallery_id}")
          end
        end

        people = get_people(json["people"])
        if people
          video.people = people
        end

        tags = get_tags(json["tags"])
        if tags
          video.tags = tags
        end

        markers = json["markers"]
        if markers
          markers.each { |marker|
            marker_id = marker["id"]
            new_marker = VideoMarker.new(id: marker_id)
            new_marker.title = marker["title"]
            new_marker.seconds = marker["seconds"]
            new_marker.end_seconds = marker["end_seconds"] if marker["end_seconds"]

            primary_tag = Tag.find_by(name: marker["primary_tag"])
            if primary_tag
              new_marker.primary_tag = primary_tag
            else
              @manager.warn("Primary tag does not exist! #{marker["primary_tag"]}")
            end

            marker_tags = get_tags(marker["tags"])
            if marker_tags
              new_marker.tags = marker_tags
            end

            video.video_markers << new_marker
          }
        end

        # Import checksums
        if json["checksums"]
          video.checksums.destroy_all
          json["checksums"].each do |checksum_data|
            Checksum.create!(
              hashable: video,
              checksum_type: checksum_data["type"],
              hash_value: checksum_data["value"]
            )
          end
        end

        file_info = json["file"]
        if file_info
          video.size = file_info["size"]
          video.duration = file_info["duration"]
          video.video_codec = file_info["video_codec"]
          video.audio_codec = file_info["audio_codec"]
          video.width = file_info["width"]
          video.height = file_info["height"]
          video.framerate = file_info["framerate"]
          video.bitrate = file_info["bitrate"]
        else
          # TODO Get FFMPEG metadata?
        end

      end

      video.save!(validate: false)
    }

    @manager.info("Video import complete")
  end

  def get_studio(studio_name)
    return nil if studio_name.blank?

    studio = Studio.find_by(name: studio_name)
    if studio
      studio
    else
      @manager.warn("Studio does not exist! #{studio_name}.")
      nil
    end
  end

  def get_tags(tag_names)
    return nil if tag_names.blank?

    tags = Tag.where(name: tag_names)

    missing_tags = tag_names - tags.pluck(:name)
    missing_tags.each { |tag_name|
      @manager.warn("Tag does not exist! #{tag_name}")
    }

    tags
  end

  def get_people(person_names)
    return nil if person_names.blank?

    people = Person.where(name: person_names)

    missing_people = person_names - people.pluck(:name)
    missing_people.each { |person_name|
      @manager.warn("Person does not exist! #{person_name}")
    }

    people
  end

  def detect_mime(data)
    return "image/jpeg" unless data
    if data[0, 4] == "\x89PNG".b
      "image/png"
    elsif data[0, 2] == "\xFF\xD8".b
      "image/jpeg"
    else
      "image/jpeg"
    end
  end
end
