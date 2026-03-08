class CreateFtsScenes < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE VIRTUAL TABLE fts_videos
      USING fts5(title, details, path, video_id UNINDEXED)
    SQL

    # Populate using the model so IDs are serialized as base36 strings
    # (raw SQL would store binary blobs that don't match model-level IDs)
    Video.rebuild_search_index_in_batches
  end

  def down
    execute "DROP TABLE IF EXISTS fts_videos"
  end
end
