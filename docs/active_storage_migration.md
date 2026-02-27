# ActiveStorage Migration Plan

## Overview
Migrate all generated media from file system + binary blobs to ActiveStorage with local disk storage.

**Key Decisions:**
- Migrate all existing content immediately (no hybrid approach)
- JSON exports will reference ActiveStorage URLs (not Base64)
- Snippets and remuxed videos will use separate models with `has_one_attached`

---

## Phase 1: Infrastructure Setup

### 1.1 Configure ActiveStorage

**File:** `config/storage.yml` (already exists)
- Keep `local:` service with `root: storage/`
- Add new services for generated media organization:
  ```yaml
  local_media:
    service: Disk
    root: <%= Rails.root.join("storage/media") %>
  local_thumbnails:
    service: Disk
    root: <%= Rails.root.join("storage/thumbnails") %>
  local_previews:
    service: Disk
    root: <%= Rails.root.join("storage/previews") %>
  local_snippets:
    service: Disk
    root: <%= Rails.root.join("storage/snippets") %>
  local_transcodes:
    service: Disk
    root: <%= Rails.root.join("storage/transcodes") %>
  ```

**File:** `config/environments/development.rb`
- Configure ActiveStorage to use `local_media` as default
- Add variant processor (vips or mini_magick)

### 1.2 Docker Configuration Updates

**File:** `docker-compose.yml`
- Add bind mount for ActiveStorage storage:
  ```yaml
  volumes:
    - ${STASH_DATA}:${STASH_DATA}:ro
    - ${STASH_METADATA}:${STASH_METADATA}
    - ${STASH_CACHE}:${STASH_CACHE}
    - ${STASH_DOWNLOADS}:${STASH_DOWNLOADS}
    - ${STASH_STORAGE}:/app/storage  # NEW
  ```

**File:** `.env.example`
- Add `STASH_STORAGE=/path/to/storage` for bind mount path

**File:** `docker/nginx.conf` (if needed)
- Update X-Accel-Redirect paths for ActiveStorage
- ActiveStorage uses `/rails/active_storage/...` paths by default

---

## Phase 2: Database Schema Changes

### 2.1 Add ActiveStorage Tables

```bash
rails active_storage:install
```

This creates:
- `active_storage_blobs`
- `active_storage_attachments`
- `active_storage_variant_records`

### 2.2 Update Existing Models

**Performer Model**
```ruby
class Performer < ApplicationRecord
  has_one_attached :image

  # Remove old validation (image_exists) after migration
  # validates_uniqueness_of :checksum
end
```

**Studio Model**
```ruby
class Studio < ApplicationRecord
  has_one_attached :image
end
```

**Scene Model**
```ruby
class Scene < ApplicationRecord
  has_one_attached :screenshot       # Full-size thumbnail
  has_one_attached :thumbnail        # Small thumbnail (320px)
  has_one_attached :preview_video    # MP4 preview clip
  has_one_attached :preview_webp     # Animated WebP preview
  has_one_attached :vtt_sprite       # Sprite sheet image
  has_one_attached :vtt_file         # VTT file

  has_many_attached :transcodes      # Multiple transcode versions
end
```

**SceneMarker Model**
```ruby
class SceneMarker < ApplicationRecord
  has_one_attached :preview_video    # MP4 clip at marker
  has_one_attached :preview_webp     # WebP clip at marker
end
```

**Gallery Model**
```ruby
class Gallery < ApplicationRecord
  has_many_attached :images          # Extracted images from ZIP
end
```

### 2.3 Create New Models for Future Features

**Transcode Model** (for remuxed/transcoded videos)
```ruby
# db/migrate/..._create_transcodes.rb
class CreateTranscodes < ActiveRecord::Migration[8.1]
  def change
    create_table :transcodes do |t|
      t.references :scene, null: false, foreign_key: true
      t.string :format              # "mp4", "webm", etc.
      t.string :video_codec         # "h264", "h265", "vp9", etc.
      t.string :audio_codec         # "aac", "opus", etc.
      t.integer :width
      t.integer :height
      t.integer :bitrate
      t.integer :file_size
      t.string :quality_preset      # "high", "medium", "low"
      t.string :status              # "pending", "processing", "ready", "failed"
      t.json :metadata              # FFmpeg probe data
      t.timestamps

      t.index :status
      t.index [:scene_id, :quality_preset], unique: true
    end
  end
end
```

**Transcode Model**
```ruby
class Transcode < ApplicationRecord
  belongs_to :scene
  has_one_attached :video_file

  enum status: %w[pending processing ready failed]
end
```

**Snippet Model**
```ruby
# db/migrate/..._create_snippets.rb
class CreateSnippets < ActiveRecord::Migration[8.1]
  def change
    create_table :snippets do |t|
      t.references :scene, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title
      t.decimal :start_time, precision: 10, scale: 2
      t.decimal :end_time, precision: 10, scale: 2
      t.decimal :duration, precision: 10, scale: 2
      t.string :checksum              # MD5 of source+times
      t.string :status
      t.datetime :expires_at          # Auto-deletion
      t.timestamps

      t.index :user_id
      t.index :expires_at
      t.index :checksum, unique: true
    end
  end
end
```

**Snippet Model**
```ruby
class Snippet < ApplicationRecord
  belongs_to :scene
  belongs_to :user
  has_one_attached :video_file
  has_one_attached :thumbnail

  enum status: %w[pending processing ready failed]

  before_validation :calculate_duration, on: :create
  before_validation :generate_checksum, on: :create

  private

  def calculate_duration
    self.duration = end_time - start_time if start_time && end_time
  end

  def generate_checksum
    data = "#{scene.checksum}-#{start_time}-#{end_time}"
    self.checksum = Digest::MD5.hexdigest(data)
  end
end
```

---

## Phase 3: Data Migration

### 3.1 Migration Strategy Overview

Create a comprehensive migration script that:
1. Migrates binary blobs (performers, studios)
2. Migrates file-based content (thumbnails, previews, VTTs, etc.)
3. Updates controller serving logic
4. Updates generator jobs
5. Backs up old data before deletion

### 3.2 Create Migration File

```bash
rails g migration MigrateToActiveStorage
```

**File:** `db/migrate/..._migrate_to_active_storage.rb`

```ruby
class MigrateToActiveStorage < ActiveRecord::Migration[8.1]
  def up
    say "Starting ActiveStorage migration...", true

    # === 1. Migrate Performer Images ===
    say_with_time "Migrating performer images..." do
      Performer.find_each do |performer|
        next if performer.image.blank?

        # Attach to ActiveStorage
        performer.image.attach(
          io: StringIO.new(performer.image_binary),
          filename: "performer-#{performer.checksum}.jpg",
          content_type: detect_mime_type(performer.image_binary)
        )
      end
    end

    # === 2. Migrate Studio Images ===
    say_with_time "Migrating studio images..." do
      Studio.find_each do |studio|
        next if studio.image.blank?

        studio.image.attach(
          io: StringIO.new(studio.image_binary),
          filename: "studio-#{studio.checksum}.jpg",
          content_type: detect_mime_type(studio.image_binary)
        )
      end
    end

    # === 3. Migrate Scene Thumbnails ===
    say_with_time "Migrating scene thumbnails..." do
      screenshot_dir = File.join(Stash::STASH_SCREENSHOTS_DIRECTORY)

      Scene.find_each do |scene|
        # Full screenshot
        screenshot_path = File.join(screenshot_dir, "#{scene.checksum}.jpg")
        if File.exist?(screenshot_path)
          scene.screenshot.attach(
            io: File.open(screenshot_path),
            filename: "scene-#{scene.checksum}-screenshot.jpg",
            content_type: 'image/jpeg'
          )
        end

        # Thumbnail
        thumb_path = File.join(screenshot_dir, "#{scene.checksum}.thumb.jpg")
        if File.exist?(thumb_path)
          scene.thumbnail.attach(
            io: File.open(thumb_path),
            filename: "scene-#{scene.checksum}-thumb.jpg",
            content_type: 'image/jpeg'
          )
        end
      end
    end

    # === 4. Migrate Scene Previews ===
    say_with_time "Migrating scene previews..." do
      preview_dir = File.join(Stash::STASH_SCREENSHOTS_DIRECTORY)

      Scene.find_each do |scene|
        # MP4 preview
        mp4_path = File.join(preview_dir, "#{scene.checksum}.mp4")
        if File.exist?(mp4_path)
          scene.preview_video.attach(
            io: File.open(mp4_path),
            filename: "scene-#{scene.checksum}-preview.mp4",
            content_type: 'video/mp4'
          )
        end

        # WebP preview
        webp_path = File.join(preview_dir, "#{scene.checksum}.webp")
        if File.exist?(webp_path)
          scene.preview_webp.attach(
            io: File.open(webp_path),
            filename: "scene-#{scene.checksum}-preview.webp",
            content_type: 'image/webp'
          )
        end
      end
    end

    # === 5. Migrate VTT Sprite Sheets ===
    say_with_time "Migrating VTT sprite sheets..." do
      vtt_dir = File.join(Stash::STASH_VTT_DIRECTORY)

      Scene.find_each do |scene|
        # Sprite image
        sprite_path = File.join(vtt_dir, "#{scene.checksum}_sprite.jpg")
        if File.exist?(sprite_path)
          scene.vtt_sprite.attach(
            io: File.open(sprite_path),
            filename: "scene-#{scene.checksum}-sprite.jpg",
            content_type: 'image/jpeg'
          )
        end

        # VTT file
        vtt_path = File.join(vtt_dir, "#{scene.checksum}_thumbs.vtt")
        if File.exist?(vtt_path)
          scene.vtt_file.attach(
            io: File.open(vtt_path),
            filename: "scene-#{scene.checksum}-thumbs.vtt",
            content_type: 'text/vtt'
          )
        end
      end
    end

    # === 6. Migrate Transcoded Videos ===
    say_with_time "Migrating transcodes..." do
      transcode_dir = File.join(Stash::STASH_TRANSCODE_DIRECTORY)

      Scene.find_each do |scene|
        transcode_path = File.join(transcode_dir, "#{scene.checksum}.mp4")
        if File.exist?(transcode_path)
          # Create Transcode record
          transcode = Transcode.find_or_create_by(
            scene: scene,
            quality_preset: 'default'
          )
          transcode.update(
            format: 'mp4',
            video_codec: 'h264',
            audio_codec: 'aac',
            status: 'ready',
            file_size: File.size(transcode_path)
          )

          # Attach video
          transcode.video_file.attach(
            io: File.open(transcode_path),
            filename: "scene-#{scene.checksum}-transcode.mp4",
            content_type: 'video/mp4'
          )
        end
      end
    end

    # === 7. Migrate Scene Marker Previews ===
    say_with_time "Migrating scene marker previews..." do
      markers_dir = File.join(Stash::STASH_MARKERS_DIRECTORY)

      SceneMarker.find_each do |marker|
        marker_dir = File.join(markers_dir, marker.scene.checksum)
        next unless Dir.exist?(marker_dir)

        # MP4 preview
        mp4_path = File.join(marker_dir, "#{marker.seconds}.mp4")
        if File.exist?(mp4_path)
          marker.preview_video.attach(
            io: File.open(mp4_path),
            filename: "marker-#{marker.id}-#{marker.seconds}.mp4",
            content_type: 'video/mp4'
          )
        end

        # WebP preview
        webp_path = File.join(marker_dir, "#{marker.seconds}.webp")
        if File.exist?(webp_path)
          marker.preview_webp.attach(
            io: File.open(webp_path),
            filename: "marker-#{marker.id}-#{marker.seconds}.webp",
            content_type: 'image/webp'
          )
        end
      end
    end

    # === 8. Migrate Gallery Images ===
    say_with_time "Migrating gallery images..." do
      cache_dir = Stash::STASH_CACHE_DIRECTORY

      Gallery.find_each do |gallery|
        gallery_dir = File.join(cache_dir, gallery.checksum)
        next unless Dir.exist?(gallery_dir)

        Dir.glob(File.join(gallery_dir, '*')).each do |file|
          next if file.include?('_thumb.') || File.directory?(file)

          gallery.images.attach(
            io: File.open(file),
            filename: File.basename(file),
            content_type: detect_mime_type(File.binread(file))
          )
        end
      end
    end

    say "ActiveStorage migration complete!", true
  end

  def down
    say "Rolling back ActiveStorage migration...", true

    # Detach all ActiveStorage attachments
    Performer.find_each { |p| p.image.purge }
    Studio.find_each { |s| s.image.purge }
    Scene.find_each { |s| s.screenshot&.purge; s.thumbnail&.purge; s.preview_video&.purge; s.preview_webp&.purge; s.vtt_sprite&.purge; s.vtt_file&.purge; s.transcodes.each { |t| t.video_file&.purge } }
    SceneMarker.find_each { |m| m.preview_video&.purge; m.preview_webp&.purge }
    Gallery.find_each { |g| g.images.purge }
    Transcode.find_each { |t| t.video_file&.purge }

    say "Rollback complete!", true
  end

  private

  def detect_mime_type(data)
    return 'image/jpeg' if data[0, 2] == "\xFF\xD8".b
    return 'image/png' if data[0, 4] == "\x89PNG".b
    'image/jpeg'
  end
end
```

### 3.3 Remove Old Binary Columns (After Verification)

```bash
rails g migration RemoveBinaryColumnsFromModels
```

**File:** `db/migrate/..._remove_binary_columns_from_models.rb`

```ruby
class RemoveBinaryColumnsFromModels < ActiveRecord::Migration[8.1]
  def change
    remove_column :performers, :image
    remove_column :studios, :image
  end
end
```

---

## Phase 4: Code Updates

### 4.1 Update Model Methods

**File:** `app/models/performer.rb`

```ruby
class Performer < ApplicationRecord
  include Filterable

  has_one_attached :image

  has_and_belongs_to_many :scenes
  has_and_belongs_to_many :galleries

  validates :image, presence: true
  validates_uniqueness_of :checksum

  scoped_search on: [:name, :checksum, :birthdate, :ethnicity]

  default_scope { order(name: :asc) }
  scope :filter_favorites, -> (favorite) { where(favorite: favorite) }

  def age(date: Date.today)
    a = date.year - birthdate.year
    a = a - 1 if (birthdate.month > date.month || (birthdate.month >= date.month && birthdate.day > date.day))
    return a
  end
end
```

**File:** `app/models/studio.rb`

```ruby
class Studio < ApplicationRecord
  include Filterable

  has_one_attached :image

  has_many :scenes
  has_many :galleries

  validates :image, presence: true
  validates :name, presence: true, uniqueness: true
end
```

**File:** `app/models/scene.rb`

```ruby
class Scene < ApplicationRecord
  include Filterable
  include Taggable

  has_one_attached :screenshot
  has_one_attached :thumbnail
  has_one_attached :preview_video
  has_one_attached :preview_webp
  has_one_attached :vtt_sprite
  has_one_attached :vtt_file
  has_many_attached :transcodes

  belongs_to :studio, optional: true
  has_and_belongs_to_many :performers
  has_and_belongs_to_many :galleries
  has_and_belongs_to_many :tags
  has_many :scene_markers

  # Keep existing methods but update to use ActiveStorage
  def stream_file_path
    # Check for ActiveStorage transcode
    if transcodes.any?
      transcodes.first.video_file.service_url
    else
      path
    end
  end

  def screenshot_path(width: nil)
    screenshot.variant(resize: width) if screenshot.attached? && width
    screenshot.url if screenshot.attached?
  end

  def vtt_data
    vtt_file.download if vtt_file.attached?
  end
end
```

### 4.2 Update Controllers

**File:** `app/controllers/performers_controller.rb`

```ruby
class PerformersController < ApplicationController
  before_action :set_performer, only: [:show, :image]

  def index
    @performers = Performer.all
    @performers = @performers.search_for(params[:q]) if params[:q].present?
    @performers = @performers.filter_favorites(params[:favorites] == "true") if params[:favorites].present?
    @pagy, @performers = pagy(@performers, limit: 48)
  end

  def show
    @pagy, @scenes = pagy(@performer.scenes.includes(:studio))
  end

  def image
    if stale?(etag: @performer.image.blob.checksum)
      expires_in 1.week
      redirect_to @performer.image.url(allow_host: true), status: :moved_permanently
    end
  end

  private

  def set_performer
    @performer = Performer.find(params[:id])
  end
end
```

**File:** `app/controllers/scenes_controller.rb`

```ruby
class ScenesController < ApplicationController
  before_action :set_scene, only: [:show, :stream, :screenshot, :preview, :webp, :vtt, :chapter_vtt]

  def index
    @scenes = Scene.includes(:studio, :performers)
    @scenes = @scenes.search_for(params[:q]) if params[:q].present?
    @scenes = @scenes.filter(scene_filter_params) if scene_filter_params.any?

    if params[:sort].present?
      allowed = %w[title date rating duration path]
      sort_col = allowed.include?(params[:sort]) ? params[:sort] : "path"
      direction = params[:direction] == "desc" ? "desc" : "asc"
      @scenes = @scenes.reorder("scenes.#{sort_col} #{direction}")
    end

    @pagy, @scenes = pagy(@scenes)

    @studios = Studio.order(:name)
    @performers = Performer.order(:name)
    @tags = Tag.order(:name)
  end

  def show
    @markers = @scene.scene_markers.includes(:primary_tag)
  end

  def stream
    # Serve from ActiveStorage or original file
    if @scene.transcodes.any?
      redirect_to @scene.transcodes.first.video_file.url(allow_host: true)
    else
      send_file @scene.path, disposition: 'inline'
    end
  end

  def screenshot
    if @scene.screenshot.attached?
      redirect_to @scene.screenshot.url(allow_host: true)
    else
      generate_screenshot_on_demand
    end
  end

  def preview
    if @scene.preview_video.attached?
      redirect_to @scene.preview_video.url(allow_host: true)
    else
      head :not_found
    end
  end

  def webp
    if @scene.preview_webp.attached?
      redirect_to @scene.preview_webp.url(allow_host: true)
    else
      screenshot
    end
  end

  def vtt
    if params[:format] == "jpg"
      if @scene.vtt_sprite.attached?
        redirect_to @scene.vtt_sprite.url(allow_host: true)
      else
        head :not_found
      end
    else
      if @scene.vtt_file.attached?
        send_data @scene.vtt_file.download, content_type: 'text/vtt', disposition: 'inline'
      else
        head :not_found
      end
    end
  end

  private

  def set_scene
    if params[:id].include?('.vtt')
      params[:id].slice!('_thumbs.vtt')
      params[:format] = 'vtt'
    end
    if params[:id].include?('.jpg')
      params[:id].slice!('_sprite.jpg')
      params[:format] = 'jpg'
    end

    @scene = Scene.find_by(checksum: params[:id]) || Scene.find(params[:id])
  end

  def generate_screenshot_on_demand
    # Generate screenshot using FFmpeg and attach to ActiveStorage
    # ... implementation
  end

  def scene_filter_params
    params.permit(:rating, :resolution, :studio_id, :has_markers,
                  tags: [], filter_performers: [])
          .to_h
          .reject { |_, v| v.blank? }
  end
end
```

**File:** `app/controllers/galleries_controller.rb`

```ruby
class GalleriesController < ApplicationController
  before_action :set_gallery

  def show
  end

  def file
    index = params[:index].to_i

    if @gallery.images.attached? && index < @gallery.images.count
      redirect_to @gallery.images[index].url(allow_host: true)
    else
      # Fallback to old extraction method if images not in ActiveStorage
      extract_and_serve_image(index)
    end
  end

  private

  def set_gallery
    @gallery = Gallery.find(params[:id])
  end

  def extract_and_serve_image(index)
    # Old extraction logic from zip
    # ... implementation
  end
end
```

### 4.3 Update Generator Jobs

**File:** `lib/stash/tasks/scan.rb`

```ruby
module Stash
  module Tasks
    class Scan
      def perform
        Scene.all.find_each do |scene|
          generate_screenshot(scene)
          generate_thumbnail(scene)
        end
      end

      private

      def generate_screenshot(scene)
        # Use FFmpeg to extract screenshot
        path = extract_screenshot_ffmpeg(scene.path)

        # Attach to ActiveStorage
        scene.screenshot.attach(
          io: File.open(path),
          filename: "scene-#{scene.checksum}-screenshot.jpg",
          content_type: 'image/jpeg'
        )

        # Cleanup temp file
        File.delete(path)
      end

      def generate_thumbnail(scene)
        # Create variant from screenshot
        return unless scene.screenshot.attached?

        variant = scene.screenshot.variant(resize: '320>')
        thumb_io = ActiveStorage::Blob::IO.new(variant.open, 'image/jpeg')

        scene.thumbnail.attach(
          io: thumb_io,
          filename: "scene-#{scene.checksum}-thumb.jpg",
          content_type: 'image/jpeg'
        )
      end
    end
  end
end
```

**File:** `lib/stash/tasks/generate_sprite.rb`

```ruby
module Stash
  module Tasks
    class GenerateSprite
      def perform(scene)
        # Generate sprite using VTT generator
        generator = Stash::Movie::VTTGenerator.new(scene.path)
        sprite_path, vtt_path = generator.generate

        # Attach to ActiveStorage
        scene.vtt_sprite.attach(
          io: File.open(sprite_path),
          filename: "scene-#{scene.checksum}-sprite.jpg",
          content_type: 'image/jpeg'
        )

        scene.vtt_file.attach(
          io: File.open(vtt_path),
          filename: "scene-#{scene.checksum}-thumbs.vtt",
          content_type: 'text/vtt'
        )

        # Cleanup temp files
        File.delete(sprite_path)
        File.delete(vtt_path)
      end
    end
  end
end
```

**File:** `lib/stash/tasks/generate_transcode.rb`

```ruby
module Stash
  module Tasks
    class GenerateTranscode
      def perform(scene, quality: 'medium')
        transcode = Transcode.find_or_create_by(
          scene: scene,
          quality_preset: quality
        )
        transcode.update(status: 'processing')

        # Transcode using FFmpeg
        output_path = transcode_ffmpeg(scene.path)

        # Get video metadata
        probe = FFMPEG::Movie.new(output_path)
        transcode.update(
          format: 'mp4',
          video_codec: probe.video_codec,
          audio_codec: probe.audio_codec,
          width: probe.width,
          height: probe.height,
          bitrate: probe.bitrate,
          file_size: File.size(output_path),
          status: 'ready'
        )

        # Attach to ActiveStorage
        transcode.video_file.attach(
          io: File.open(output_path),
          filename: "scene-#{scene.checksum}-transcode-#{quality}.mp4",
          content_type: 'video/mp4'
        )

        # Cleanup temp file
        File.delete(output_path)
      end

      private

      def transcode_ffmpeg(input_path)
        # FFmpeg transcode implementation
        # ...
      end
    end
  end
end
```

### 4.4 Update JSON Export/Import

**File:** `lib/stash/tasks/export.rb`

```ruby
module Stash
  module Tasks
    class Export
      def export_performer(performer)
        {
          'checksum' => performer.checksum,
          'name' => performer.name,
          'url' => performer.url,
          'twitter' => performer.twitter,
          'instagram' => performer.instagram,
          'birthdate' => performer.birthdate,
          'ethnicity' => performer.ethnicity,
          'country' => performer.country,
          'eye_color' => performer.eye_color,
          'height' => performer.height,
          'measurements' => performer.measurements,
          'fake_tits' => performer.fake_tits,
          'career_length' => performer.career_length,
          'tattoos' => performer.tattoos,
          'piercings' => performer.piercings,
          'aliases' => performer.aliases,
          'favorite' => performer.favorite,
          'image_url' => performer.image.url,  # Changed from Base64 to URL
          'tags' => performer.tags.map(&:name)
        }
      end

      def export_studio(studio)
        {
          'checksum' => studio.checksum,
          'name' => studio.name,
          'url' => studio.url,
          'image_url' => studio.image.url  # Changed from Base64 to URL
        }
      end
    end
  end
end
```

**File:** `lib/stash/tasks/import.rb`

```ruby
module Stash
  module Tasks
    class Import
      def import_performer(data)
        performer = Performer.find_or_initialize_by(checksum: data['checksum'])
        performer.update(
          name: data['name'],
          url: data['url'],
          twitter: data['twitter'],
          instagram: data['instagram'],
          birthdate: data['birthdate'],
          ethnicity: data['ethnicity'],
          country: data['country'],
          eye_color: data['eye_color'],
          height: data['height'],
          measurements: data['measurements'],
          fake_tits: data['fake_tits'],
          career_length: data['career_length'],
          tattoos: data['tattoos'],
          piercings: data['piercings'],
          aliases: data['aliases'],
          favorite: data['favorite']
        )

        # Download image from URL if provided
        if data['image_url'] && !performer.image.attached?
          performer.image.attach(
            io: URI.open(data['image_url']),
            filename: "performer-#{data['checksum']}.jpg",
            content_type: 'image/jpeg'
          )
        end

        performer
      end
    end
  end
end
```

---

## Phase 5: NGINX Configuration

### 5.1 Update NGINX for ActiveStorage

**File:** `docker/nginx.conf`

```nginx
server {
  listen 4000;
  root /app/storage;  # Point to ActiveStorage storage

  location /rails/active_storage/ {
    # Serve ActiveStorage files directly from disk
    internal;
    alias /app/storage/;
    expires 1y;
    add_header Cache-Control "public, immutable";
  }

  location / {
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header HOST $http_host;
    proxy_set_header X-Sendfile-Type X-Accel-Redirect;
    proxy_set_header X-Accel-Mapping /=/__send_file_accel/;
    proxy_redirect off;
    proxy_pass http://localhost:3000;
  }
}
```

---

## Phase 6: Testing & Validation

### 6.1 Pre-Migration Tests

```bash
# Backup database
rails db:backup

# Count files to migrate
rails runner "
  puts 'Performers: ' + Performer.count.to_s
  puts 'Studios: ' + Studio.count.to_s
  puts 'Scenes: ' + Scene.count.to_s
  puts 'Markers: ' + SceneMarker.count.to_s
  puts 'Galleries: ' + Gallery.count.to_s

  puts 'Existing screenshots: ' + Dir.glob(File.join(Stash::STASH_SCREENSHOTS_DIRECTORY, '*.jpg')).count.to_s
  puts 'Existing previews: ' + Dir.glob(File.join(Stash::STASH_SCREENSHOTS_DIRECTORY, '*.mp4')).count.to_s
  puts 'Existing VTT sprites: ' + Dir.glob(File.join(Stash::STASH_VTT_DIRECTORY, '*.jpg')).count.to_s
"
```

### 6.2 Run Migration

```bash
rails db:migrate
```

### 6.3 Post-Migration Validation

```bash
# Verify attachments
rails runner "
  puts 'Performers with images: ' + Performer.where.associated(:image).count.to_s
  puts 'Scenes with screenshots: ' + Scene.where.associated(:screenshot).count.to_s
  puts 'Scenes with previews: ' + Scene.where.associated(:preview_video).count.to_s
  puts 'Markers with previews: ' + SceneMarker.where.associated(:preview_video).count.to_s
"

# Test file serving
curl -I http://localhost:4000/performers/1/image
curl -I http://localhost:4000/scenes/1/screenshot
```

### 6.4 Cleanup Old Files (After Verification)

```bash
# Archive old files before deletion
mv lstash_meta/screenshots lstash_meta/screenshots.bak
mv lstash_meta/vtt lstash_meta/vtt.bak
mv lstash_meta/markers lstash_meta/markers.bak
mv lstash_meta/transcodes lstash_meta/transcodes.bak

# Delete after verification
# rm -rf lstash_meta/screenshots.bak
# rm -rf lstash_meta/vtt.bak
# rm -rf lstash_meta/markers.bak
# rm -rf lstash_meta/transcodes.bak
```

---

## Phase 7: Rollback Plan

If issues arise:

```bash
# Rollback migration
rails db:rollback

# Restore old files
mv lstash_meta/screenshots.bak lstash_meta/screenshots
mv lstash_meta/vtt.bak lstash_meta/vtt
mv lstash_meta/markers.bak lstash_meta/markers
mv lstash_meta/transcodes.bak lstash_meta/transcodes
```

---

## Implementation Order

1. **Phase 1:** Configure ActiveStorage and update Docker (1 day)
2. **Phase 2:** Create new models (Transcode, Snippet) and update schema (1 day)
3. **Phase 3:** Run migration to migrate all existing content (2-3 days, depending on data size)
4. **Phase 4:** Update models, controllers, and jobs (2-3 days)
5. **Phase 5:** Update NGINX configuration (1 day)
6. **Phase 6:** Testing and validation (2 days)
7. **Phase 7:** Cleanup old files (1 day)

**Total Estimated Time:** 8-11 days

---

## Configuration Changes

**File:** `config/application.yml`

```yaml
# ActiveStorage
active_storage_service: "local"

# Transcoding default settings
default_transcode_quality: "medium"
default_transcode_format: "mp4"

# Snippet settings
snippet_default_ttl_hours: 24
snippet_max_duration_seconds: 300

# Cleanup settings
cleanup_expired_snippets_after_days: 7
cleanup_failed_transcodes_after_days: 1
```

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Large file migration takes too long | High | Run in batches, use find_each with proper batch size |
| Disk space usage doubles during migration | Medium | Ensure sufficient storage, delete old files after verification |
| ActiveStorage URLs break existing clients | Medium | Keep old paths working with redirects during transition |
| Loss of data if migration fails | High | Full database backup before migration, archive old files |
| Performance degradation during migration | Low | Run during low-traffic hours, monitor system resources |

---

## Success Criteria

- [ ] All performer/studio images migrated to ActiveStorage
- [ ] All scene thumbnails/previews migrated
- [ ] All VTT sprite sheets migrated
- [ ] All transcodes migrated
- [ ] All marker previews migrated
- [ ] All gallery images migrated
- [ ] Controllers serve files via ActiveStorage URLs
- [ ] Generator jobs create files in ActiveStorage
- [ ] JSON exports reference ActiveStorage URLs
- [ ] Old files archived and removed
- [ ] All tests pass
- [ ] No performance degradation observed
