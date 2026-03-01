class CreateScenes < ActiveRecord::Migration[8.1]
  def change
    create_table :scenes, id: :uuid do |t|
      t.string :audio_codec
      t.integer :bitrate
      t.string :checksum
      t.date :date
      t.string :details
      t.decimal :duration, precision: 7, scale: 2
      t.decimal :framerate, precision: 7, scale: 2
      t.integer :height
      t.json :hls_segment_durations
      t.references :library, type: :uuid, foreign_key: true
      t.string :path
      t.integer :rating
      t.string :size
      t.references :studio, type: :uuid, foreign_key: true
      t.string :title
      t.string :url
      t.string :video_codec
      t.integer :width

      t.timestamps
    end

    add_index :scenes, :checksum
    add_index :scenes, :path, unique: true
  end
end
