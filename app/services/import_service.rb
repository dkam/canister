class ImportService
  def initialize
  end

  def start
    @mappings = JsonUtility.mappings
    return unless @mappings

    import_people
    import_studios
    import_galleries
    import_tags

    Video.transaction {
      import_videos
    }
  end

  private

  def import_people
    people = []
    images = {}

    @mappings["people"].each.with_index(1) { |personJSON, index|
      id = personJSON["id"]
      name = personJSON["name"]
      json = JsonUtility.person id
      next unless id && name && json

      Rails.logger.info("Reading person #{index} of #{@mappings["people"].count}\r")

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

    Rails.logger.info("Importing people...")
    Person.import(people, validate: false)

    Rails.logger.info("Attaching person images...")
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

    Rails.logger.info("Person import complete")
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

      Rails.logger.info("Reading studio #{index} of #{@mappings["studios"].count}\r")

      studio = Studio.new(id: id)
      studio.name = name
      studio.url = json["url"]

      images[id] = json["image"] if json["image"].present?
      studios.push(studio)
    }

    Rails.logger.info("Importing studios...")
    Studio.import(studios, validate: false)

    Rails.logger.info("Attaching studio images...")
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

    Rails.logger.info("Studio import complete")
  end

  def import_galleries
    galleries = []
    @mappings["galleries"].each.with_index(1) { |galleryJSON, index|
      id = galleryJSON["id"]
      path = galleryJSON["path"]
      next unless id && path

      Rails.logger.info("Reading gallery #{index} of #{@mappings["galleries"].count}\r")

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

    Rails.logger.info("Importing galleries...")
    Gallery.import(galleries)
    Rails.logger.info("Gallery import complete")
  end

  def import_tags
    tag_names = []
    tags = []

    @mappings["videos"].each.with_index(1) { |videoJSON, index|
      id = videoJSON["id"]
      path = videoJSON["path"]
      unless id && path
        Rails.logger.warn("Video mapping without id and path! #{videoJSON}")
        next
      end

      Rails.logger.info("Importing tags for video #{index} of #{@mappings["videos"].count}\r")

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

    Rails.logger.info("Importing tags...")
    Tag.import(tags)
    Rails.logger.info("Tag import complete")
  end

  def import_videos
    @mappings["videos"].each.with_index(1) { |videoJSON, index|
      id = videoJSON["id"]
      path = videoJSON["path"]
      unless id && path
        Rails.logger.warn("Video mapping without id and path! #{videoJSON}")
        next
      end

      Rails.logger.info("Importing video #{index} of #{@mappings["videos"].count}\r")

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
            Rails.logger.warn("Gallery does not exist! #{gallery_id}")
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
              Rails.logger.warn("Primary tag does not exist! #{marker["primary_tag"]}")
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

    Rails.logger.info("Video import complete")
  end

  def get_studio(studio_name)
    return nil if studio_name.blank?

    studio = Studio.find_by(name: studio_name)
    if studio
      studio
    else
      Rails.logger.warn("Studio does not exist! #{studio_name}.")
      nil
    end
  end

  def get_tags(tag_names)
    return nil if tag_names.blank?

    tags = Tag.where(name: tag_names)

    missing_tags = tag_names - tags.pluck(:name)
    missing_tags.each { |tag_name|
      Rails.logger.warn("Tag does not exist! #{tag_name}")
    }

    tags
  end

  def get_people(person_names)
    return nil if person_names.blank?

    people = Person.where(name: person_names)

    missing_people = person_names - people.pluck(:name)
    missing_people.each { |person_name|
      Rails.logger.warn("Person does not exist! #{person_name}")
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
