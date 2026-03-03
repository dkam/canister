class CreateFtsScenes < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE fts_scenes
      USING fts5(title, details, path, scene_id UNINDEXED)
    SQL

    # Populate using the model so IDs are serialized as base36 strings
    # (raw SQL would store binary blobs that don't match model-level IDs)
    Scene.rebuild_search_index_in_batches
  end

  def down
    execute "DROP TABLE IF EXISTS fts_scenes"
  end
end
