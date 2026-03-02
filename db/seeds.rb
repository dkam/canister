Library.find_or_create_by!(name: "Local") do |lib|
  lib.path = ENV.fetch("VIDEO_PATH", "/videos")
  lib.kind = "local"
end
