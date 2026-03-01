class AddEndSecondsToSceneMarkers < ActiveRecord::Migration[8.1]
  def change
    add_column :scene_markers, :end_seconds, :decimal
  end
end
