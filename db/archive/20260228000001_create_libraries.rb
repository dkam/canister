class CreateLibraries < ActiveRecord::Migration[8.1]
  def change
    create_table :libraries do |t|
      t.string :name, null: false
      t.string :path, null: false
      t.string :kind, null: false, default: 'local'
      t.boolean :read_only, null: false, default: false
      t.string :default_video_kind, null: false, default: 'video'
      t.timestamps
    end
  end
end
