# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rails db:seed command (or created alongside the database with db:setup).
#
# Examples:
#
#   movies = Movie.create([{ name: 'Star Wars' }, { name: 'Lord of the Rings' }])
#   Character.create(name: 'Luke', movie: movies.first)

Library.find_or_create_by(path: ENV.fetch('DEFAULT_LIBRARY_PATH', Rails.root.join('videos').to_s)) do |lib|
  lib.name = 'Default'
  lib.kind = 'local'
  lib.read_only = false
  lib.default_video_kind = 'video'
end
