class CreateSceneMarkers < ActiveRecord::Migration[8.1]
  def change
    create_table :scene_markers, id: :uuid do |t|
      t.decimal :end_seconds
      t.references :primary_tag, type: :uuid, null: false, foreign_key: { to_table: :tags }
      t.references :scene, type: :uuid, null: false, foreign_key: true
      t.decimal :seconds, null: false
      t.string :title, null: false

      t.timestamps
    end
  end
end
