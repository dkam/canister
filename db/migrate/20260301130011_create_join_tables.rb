class CreateJoinTables < ActiveRecord::Migration[8.1]
  def change
    create_table :galleries_performers, id: false do |t|
      t.uuid :gallery_id, null: false
      t.uuid :performer_id, null: false
    end
    add_index :galleries_performers, :gallery_id
    add_index :galleries_performers, :performer_id

    create_table :performers_scenes, id: false do |t|
      t.uuid :performer_id, null: false
      t.uuid :scene_id, null: false
    end
    add_index :performers_scenes, :performer_id
    add_index :performers_scenes, :scene_id
  end
end
