module JsonUtility
  @@manager = MediaManager.instance

  def self.mappings
    return nil unless File.exist? Canister::STASH_MAPPINGS_FILE
    parse Canister::STASH_MAPPINGS_FILE
  end

  def self.save_mappings(json:)
    @@manager.info "Saving mapping file..."
    write_json path: Canister::STASH_MAPPINGS_FILE, json: json
  end

  def self.scraped
    return nil unless File.exist? Canister::STASH_SCRAPED_FILE
    parse Canister::STASH_SCRAPED_FILE
  end

  def self.save_scraped(json:)
    @@manager.info "Saving scraped file..."
    write_json path: Canister::STASH_SCRAPED_FILE, json: json
  end

  def self.person(id)
    path = File.join(Canister::STASH_PEOPLE_DIRECTORY, "#{id}.json")
    return nil unless File.exist? path
    parse path
  end

  def self.save_person(id:, json:)
    path = File.join(Canister::STASH_PEOPLE_DIRECTORY, "#{id}.json")
    @@manager.info "Saving person to #{id}.json..."
    write_json path: path, json: json
  end

  def self.video(id)
    path = File.join(Canister::STASH_VIDEOS_DIRECTORY, "#{id}.json")
    return nil unless File.exist? path
    parse path
  end

  def self.save_video(id:, json:)
    path = File.join(Canister::STASH_VIDEOS_DIRECTORY, "#{id}.json")
    @@manager.info "Saving video to #{id}.json..."
    write_json path: path, json: json
  end

  def self.gallery(id)
    path = File.join(Canister::STASH_GALLERIES_DIRECTORY, "#{id}.json")
    return nil unless File.exist? path
    parse path
  end

  def self.save_gallery(id:, json:)
    path = File.join(Canister::STASH_GALLERIES_DIRECTORY, "#{id}.json")
    @@manager.info "Saving gallery to #{id}.json..."
    write_json path: path, json: json
  end

  def self.studio(id)
    path = File.join(Canister::STASH_STUDIOS_DIRECTORY, "#{id}.json")
    return nil unless File.exist? path
    parse path
  end

  def self.save_studio(id:, json:)
    path = File.join(Canister::STASH_STUDIOS_DIRECTORY, "#{id}.json")
    @@manager.info "Saving studio to #{id}.json..."
    write_json path: path, json: json
  end

  private

  def self.parse(json_file)
    file = File.read json_file
    ::JSON.parse file
  rescue ::JSON::ParserError => e
    @@manager.warn "Failed to parse json file #{json_file}! Exception: #{e}"
  end

  def self.write_json(path:, json:)
    File.write(path, ::JSON.pretty_generate(json))
  end
end
