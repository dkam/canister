class AddHlsSegmentDurationsToScenes < ActiveRecord::Migration[8.1]
  def change
    add_column :scenes, :hls_segment_durations, :json
  end
end
