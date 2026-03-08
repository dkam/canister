namespace :checksums do
  desc "Calculate MD5 hashes for all videos"
  task calculate_md5: :environment do
    require "digest/md5"

    Video.find_each.with_index do |video, i|
      next if video.checksum_value(type: :md5)
      next unless File.exist?(video.path)

      md5 = Digest::MD5.file(video.path).hexdigest
      Checksum.create!(hashable: video, checksum_type: :md5, hash_value: md5)
      puts "#{i}: Video #{video.id}: #{md5}"
    end
    puts "MD5 calculation complete!"
  end
end
