namespace :checksums do
  desc "Calculate MD5 hashes for all scenes"
  task calculate_md5: :environment do
    require "digest/md5"

    Scene.find_each.with_index do |scene, i|
      next if scene.checksum_value(type: :md5)
      next unless File.exist?(scene.path)

      md5 = Digest::MD5.file(scene.path).hexdigest
      Checksum.create!(hashable: scene, checksum_type: :md5, hash_value: md5)
      puts "#{i}: Scene #{scene.id}: #{md5}"
    end
    puts "MD5 calculation complete!"
  end
end
