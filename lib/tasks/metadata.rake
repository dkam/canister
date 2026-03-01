namespace :metadata do
  desc "Import JSON metadata"
  task import: ["db:drop", "db:create", "db:migrate"] do
    Canister::Manager.instance.import(job_id: "rake")
  end

  desc "Export JSON metadata."
  task export: :environment do
    Canister::Manager.instance.export(job_id: "rake")
  end

  desc "Scan the stash directory for new files"
  task scan: :environment do
    Canister::Manager.instance.scan(job_id: "rake")
  end

  desc "Generates sprites and a VTT file for scrubbing video"
  task generate_sprites: :environment do
    Canister::Manager.instance.generate(
      job_id: "rake",
      sprites: true,
      previews: false,
      markers: false,
      transcodes: false
    )
  end

  desc "Generates webm files for mouseover previews"
  task generate_previews: :environment do
    Canister::Manager.instance.generate(
      job_id: "rake",
      sprites: false,
      previews: true,
      markers: false,
      transcodes: false
    )
  end

  desc "Generates transcodes for videos that dont support HTML5 video"
  task generate_transcodes: :environment do
    Canister::Manager.instance.generate(
      job_id: "rake",
      sprites: false,
      previews: false,
      markers: false,
      transcodes: true
    )
  end

  desc "Generates marker previews"
  task generate_marker_previews: :environment do
    Canister::Manager.instance.generate(
      job_id: "rake",
      sprites: false,
      previews: false,
      markers: true,
      transcodes: false
    )
  end

  desc "Generates all"
  task generate_all: :environment do
    Canister::Manager.instance.generate(job_id: "rake")
  end

  desc "Recalculate checksums for all scenes using xxhash (run after switching from MD5)"
  task recalculate_checksums: :environment do
    scenes = Scene.all
    puts "Recalculating checksums for #{scenes.count} scenes..."
    scenes.each do |scene|
      next unless File.exist?(scene.path)
      old_checksum = scene.checksum_value(type: :xxhash)
      new_checksum = XXhash.xxh64(File.binread(scene.path)).to_s(16)

      checksum_record = scene.checksums.find_or_initialize_by(checksum_type: :xxhash)
      checksum_record.hash_value = new_checksum
      checksum_record.save!

      puts "#{scene.path}: #{old_checksum} → #{new_checksum}"
    end
    puts "Done. Run metadata:cleanup to remove old transcode files, then metadata:process_videos to regenerate."
  end

  desc "Queue remux/transcode jobs for all scenes needing processing"
  task process_videos: :environment do
    scenes = Scene.needing_processing
    puts "Queuing #{scenes.count} scenes for processing..."
    scenes.each { |scene| PrepareVideoJob.perform_later(scene.id) }
  end

  desc "Cleanup generated files for missing scenes"
  task cleanup: :environment do
    Canister::Manager.instance.clean(job_id: "rake")
  end
end
