class CreateJoinTables < ActiveRecord::Migration[8.1]
  def change
    create_table :galleries_people, id: false do |t|
      t.uuid :gallery_id, null: false
      t.uuid :person_id, null: false
    end
    add_index :galleries_people, :gallery_id
    add_index :galleries_people, :person_id

    create_table :people_videos, id: false do |t|
      t.uuid :person_id, null: false
      t.uuid :video_id, null: false
    end
    add_index :people_videos, :person_id
    add_index :people_videos, :video_id
  end
end
