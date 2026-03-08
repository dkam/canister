class CreateDefaultLibrary < ActiveRecord::Migration[8.1]
  def up
    Library.find_or_create_by!(name: "Local") do |lib|
      lib.path = ENV.fetch("VIDEO_PATH", "/videos")
      lib.kind = "local"
    end
  end

  def down
    Library.find_by(name: "Local")&.destroy
  end
end
