class ConvertHlsSegmentDurationsToHash < ActiveRecord::Migration[8.1]
  def up
    # Clear existing array-format durations — they'll be regenerated as hashes
    # by the new primary process on next play.
    execute "UPDATE videos SET hls_segment_durations = NULL WHERE hls_segment_durations IS NOT NULL"
  end

  def down
    # No-op: durations are regenerated automatically
  end
end
