class MigrateToChecksums < ActiveRecord::Migration[8.1]
  def up
    require_relative "../../lib/open_subtitles_hash"

    # Migrate scenes - calculate both opensubtitles and xxhash
    Scene.find_each.with_index do |scene, i|
      old_checksum = scene.read_attribute(:checksum)
      next unless old_checksum

      # Create xxhash (existing)
      Checksum.create!(
        hashable: scene,
        checksum_type: :xxhash,
        hash_value: old_checksum
      )

      # Calculate opensubtitles hash if file exists
      if File.exist?(scene.path)
        begin
          os_hash = OpenSubtitlesHash.compute_hash(scene.path).downcase
          Checksum.create!(
            hashable: scene,
            checksum_type: :opensubtitles,
            hash_value: os_hash
          )
        rescue => e
          puts "Error calculating OS hash for scene #{scene.id}: #{e.message}"
        end
      end

      puts "#{i}: Scene #{scene.id}" if (i + 1) % 10 == 0
    end

    # Migrate galleries - xxhash only
    Gallery.find_each do |gallery|
      old_checksum = gallery.read_attribute(:checksum)
      next unless old_checksum

      Checksum.create!(
        hashable: gallery,
        checksum_type: :xxhash,
        hash_value: old_checksum
      )
    end

    puts "\n✓ Checksum migration complete!"
    puts "Next: Run 'rails db:migrate' to remove old checksum columns"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
