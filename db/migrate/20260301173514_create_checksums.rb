class CreateChecksums < ActiveRecord::Migration[8.1]
  def change
    create_table :checksums do |t|
      t.string :hash_value, null: false
      t.string :checksum_type, null: false, default: "opensubtitles"
      t.blob :hashable_id, null: false
      t.string :hashable_type, null: false
      t.timestamps

      t.index [:hashable_type, :hashable_id, :checksum_type], name: "index_checksums_unique", unique: true
      t.index :hash_value
      t.index [:hashable_type, :hashable_id]
    end
  end
end
