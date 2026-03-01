class CreateActiveStorageTables < ActiveRecord::Migration[8.1]
  def change
    create_table :active_storage_blobs, id: :uuid do |t|
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type
      t.text :metadata
      t.string :service_name, null: false
      t.bigint :byte_size, null: false
      t.string :checksum
      t.datetime :created_at, null: false
    end
    add_index :active_storage_blobs, :key, unique: true

    # record_id is a polymorphic reference: stored as a base36 UUID string
    create_table :active_storage_attachments, id: :uuid do |t|
      t.string :name, null: false
      t.string :record_id, null: false
      t.string :record_type, null: false
      t.references :blob, type: :uuid, null: false, foreign_key: { to_table: :active_storage_blobs }
      t.datetime :created_at, null: false
    end
    add_index :active_storage_attachments,
      [ :record_type, :record_id, :name, :blob_id ],
      name: "index_active_storage_attachments_uniqueness",
      unique: true

    create_table :active_storage_variant_records, id: :uuid do |t|
      t.references :blob, type: :uuid, null: false, index: false, foreign_key: { to_table: :active_storage_blobs }
      t.string :variation_digest, null: false
    end
    add_index :active_storage_variant_records,
      [ :blob_id, :variation_digest ],
      name: "index_active_storage_variant_records_uniqueness",
      unique: true
  end
end
