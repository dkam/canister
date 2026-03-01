# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_01_130012) do
  create_table "active_storage_attachments", id: :uuid, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "galleries", id: :uuid, force: :cascade do |t|
    t.string "checksum"
    t.datetime "created_at", null: false
    t.string "ownable_id"
    t.string "ownable_type"
    t.string "path"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["ownable_type", "ownable_id"], name: "index_galleries_on_ownable_type_and_ownable_id"
  end

  create_table "galleries_performers", id: false, force: :cascade do |t|
    t.uuid "gallery_id", null: false
    t.uuid "performer_id", null: false
    t.index ["gallery_id"], name: "index_galleries_performers_on_gallery_id"
    t.index ["performer_id"], name: "index_galleries_performers_on_performer_id"
  end

  create_table "libraries", id: :uuid, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "default_video_kind", default: "video", null: false
    t.string "kind", default: "local", null: false
    t.string "name", null: false
    t.string "path", null: false
    t.boolean "read_only", default: false, null: false
    t.datetime "updated_at", null: false
  end

  create_table "performers", id: :uuid, force: :cascade do |t|
    t.string "aliases"
    t.date "birthdate"
    t.string "career_length"
    t.string "checksum"
    t.string "country"
    t.datetime "created_at", null: false
    t.string "ethnicity"
    t.string "eye_color"
    t.string "fake_tits"
    t.boolean "favorite", default: false, null: false
    t.string "height"
    t.binary "image", limit: 2097152
    t.string "instagram"
    t.string "measurements"
    t.string "name"
    t.string "piercings"
    t.string "tattoos"
    t.string "twitter"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["checksum"], name: "index_performers_on_checksum"
    t.index ["name"], name: "index_performers_on_name"
  end

  create_table "performers_scenes", id: false, force: :cascade do |t|
    t.uuid "performer_id", null: false
    t.uuid "scene_id", null: false
    t.index ["performer_id"], name: "index_performers_scenes_on_performer_id"
    t.index ["scene_id"], name: "index_performers_scenes_on_scene_id"
  end

  create_table "scene_markers", id: :uuid, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "end_seconds"
    t.uuid "primary_tag_id", null: false
    t.uuid "scene_id", null: false
    t.decimal "seconds", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["primary_tag_id"], name: "index_scene_markers_on_primary_tag_id"
    t.index ["scene_id"], name: "index_scene_markers_on_scene_id"
  end

  create_table "scenes", id: :uuid, force: :cascade do |t|
    t.string "audio_codec"
    t.integer "bitrate"
    t.string "checksum"
    t.datetime "created_at", null: false
    t.date "date"
    t.string "details"
    t.decimal "duration", precision: 7, scale: 2
    t.decimal "framerate", precision: 7, scale: 2
    t.integer "height"
    t.json "hls_segment_durations"
    t.uuid "library_id"
    t.string "path"
    t.integer "rating"
    t.string "size"
    t.uuid "studio_id"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "video_codec"
    t.integer "width"
    t.index ["checksum"], name: "index_scenes_on_checksum"
    t.index ["library_id"], name: "index_scenes_on_library_id"
    t.index ["path"], name: "index_scenes_on_path", unique: true
    t.index ["studio_id"], name: "index_scenes_on_studio_id"
  end

  create_table "scraped_items", id: :uuid, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date"
    t.string "description"
    t.integer "episode"
    t.string "gallery_filename"
    t.string "gallery_url"
    t.string "models"
    t.string "rating"
    t.uuid "studio_id", null: false
    t.string "tags"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "url"
    t.string "video_filename"
    t.string "video_url"
    t.index ["studio_id"], name: "index_scraped_items_on_studio_id"
  end

  create_table "screenshots", id: :uuid, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "scene_id", null: false
    t.float "timecode"
    t.datetime "updated_at", null: false
    t.index ["scene_id"], name: "index_screenshots_on_scene_id"
  end

  create_table "studios", id: :uuid, force: :cascade do |t|
    t.string "checksum"
    t.datetime "created_at", null: false
    t.binary "image", limit: 1048576
    t.string "name"
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["checksum"], name: "index_studios_on_checksum"
    t.index ["name"], name: "index_studios_on_name"
  end

  create_table "taggings", id: :uuid, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.uuid "tag_id"
    t.string "taggable_id"
    t.string "taggable_type"
    t.datetime "updated_at", null: false
    t.index ["tag_id"], name: "index_taggings_on_tag_id"
    t.index ["taggable_type", "taggable_id"], name: "index_taggings_on_taggable_type_and_taggable_id"
  end

  create_table "tags", id: :uuid, force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "scene_markers", "scenes"
  add_foreign_key "scene_markers", "tags", column: "primary_tag_id"
  add_foreign_key "scenes", "libraries"
  add_foreign_key "scenes", "studios"
  add_foreign_key "scraped_items", "studios"
  add_foreign_key "screenshots", "scenes"
  add_foreign_key "taggings", "tags"
end
