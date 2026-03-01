class CreateLibraries < ActiveRecord::Migration[8.1]
  def change
    create_table :libraries, id: :uuid do |t|
      t.string :name, null: false
      t.string :path, null: false
      t.string :kind, default: "local", null: false
      t.boolean :read_only, default: false, null: false
      t.string :default_video_kind, default: "video", null: false

      t.timestamps
    end
  end
end
