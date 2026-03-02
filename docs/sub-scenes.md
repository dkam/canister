# Video Manager App — Architecture Brief for Claude Code

## Stack

- Rails 8, Ruby
- Hotwire / Stimulus
- SolidQueue (background jobs, ships with Rails 8)
- `acts-as-taggable-on` for tagging
- `acts_as_list` for playlist ordering
- ffmpeg / ffprobe for video processing

---

## Tagging Conventions

- All tags via `acts-as-taggable-on` — freeform, user-defined
- **No tag hierarchy / subtags**
- Timestamps use **milliseconds** (`start_offset_ms`, `end_offset_ms`) as integers throughout — not seconds or decimal seconds
- Video type (movie, tv_show, music_video, documentary etc) is a tag, not an enum — keeps UI consistent
- Codec, resolution, duration are **not** tags — auto-detected via `ffprobe` on ingest, stored as columns, displayed as badges

---

## Models

### Scene

The central model. Represents a video file or a clip derived from one. Maximum one level of nesting — no grandchildren.

```ruby
class Scene < ApplicationRecord
  belongs_to :parent, class_name: "Scene", optional: true
  has_many :clips, class_name: "Scene", foreign_key: :parent_id
  has_many :markers, class_name: "SceneMarker"

  # Only present on clips
  attribute :start_offset_ms, :integer
  attribute :end_offset_ms, :integer

  # Auto-detected metadata (ffprobe), displayed as badges not tags
  attribute :codec, :string
  attribute :width, :integer
  attribute :height, :integer
  attribute :duration_ms, :integer
  attribute :file_path, :string
  attribute :filesize_bytes, :integer

  acts_as_taggable_on :tags

  validates :parent, absence: true, if: -> { parent&.parent_id.present? }

  def clip?
    parent_id.present?
  end

  def all_tags
    # Child scenes inherit parent tags for search — own tags take precedence
    (parent&.all_tags.to_a + tags.to_a).uniq
  end

  def chapter_vtt
    vtt = ["WEBVTT", ""]
    markers.each do |m|
      end_ms = m.end_offset_ms.present? ? m.end_offset_ms : m.start_offset_ms
      vtt.push("#{vtt_time(m.start_offset_ms)} --> #{vtt_time(end_ms)}")
      vtt.push(m.title)
      vtt.push("")
    end
    vtt.join("\n")
  end

  private

  def vtt_time(ms)
    total = ms / 1000.0
    h = (total / 3600).to_i
    m = ((total % 3600) / 60).to_i
    s = total % 60
    format("%02d:%02d:%06.3f", h, m, s)
  end
end
```

---

### SceneMarker

Lightweight ranged annotation on a Scene. Cheap to create — no file involved. The default way to annotate a moment of interest.

Can be:
1. **Exported directly** → produces a transient file for sharing (common)
2. **Promoted to a child Scene** → makes it a first-class library item (intentional, uncommon)

```ruby
class SceneMarker < ApplicationRecord
  belongs_to :scene
  has_one :clip, class_name: "Scene"   # nil until promoted

  attribute :title, :string
  attribute :start_offset_ms, :integer
  attribute :end_offset_ms, :integer   # optional — nil means point-in-time

  acts_as_taggable_on :tags

  validates :start_offset_ms, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :end_offset_ms,
            numericality: { greater_than: :start_offset_ms },
            allow_nil: true

  def ranged?
    end_offset_ms.present?
  end

  def duration_ms
    return nil unless ranged?
    end_offset_ms - start_offset_ms
  end

  def promoted?
    clip.present?
  end

  def promote!
    create_clip!(
      parent: scene,
      title: title,
      start_offset_ms: start_offset_ms,
      end_offset_ms: end_offset_ms
    ).tap { |c| c.tags = tags }
  end
end
```

---

### Playlist

Ordered collection of Scenes. Used for things like "Hottest 100 2025". Separate concept from tags — handles ordering.

```ruby
class Playlist < ApplicationRecord
  attribute :title, :string

  has_many :playlist_scenes, -> { order(:position) }
  has_many :scenes, through: :playlist_scenes
end

class PlaylistScene < ApplicationRecord
  belongs_to :playlist
  belongs_to :scene
  acts_as_list scope: :playlist
end
```

---

### Export

Transient derivative file for sharing (messages, social media). **Not** part of the content graph — never appears in search or browse. Re-generatable at any time from source. Deletable after download.

Can be created from either a `SceneMarker` or a clip `Scene`.

```ruby
class Export < ApplicationRecord
  belongs_to :scene,  optional: true
  belongs_to :marker, class_name: "SceneMarker", optional: true

  enum :preset, { messages: 0, instagram: 1, twitter: 2, archive: 3, custom: 4 }
  enum :status, { pending: 0, processing: 1, ready: 2, failed: 3 }

  attribute :file_path, :string
  attribute :filesize_bytes, :integer
  attribute :width, :integer
  attribute :height, :integer

  validates :scene, presence: true, unless: :marker
  validates :marker, presence: true, unless: :scene
end
```

**Preset targets (approximate ffmpeg params):**

| Preset | Resolution | Codec | Notes |
|---|---|---|---|
| messages | 720p | h264 | <50 MB, iMessage/WhatsApp |
| instagram | 1080p | h264 | 9:16 crop option |
| twitter | 720p | h264 | ≤140s |
| archive | source res | h264 | high bitrate |
| custom | user-defined | user-defined | |

---

## Content Hierarchy

```
Scene (parent — full video file)
  ├── SceneMarker (lightweight annotation, ranged or point-in-time)
  │     ├── → Export (share directly, no Scene needed)
  │     └── → promote! → clip Scene (intentional, uncommon)
  └── Scene (clip — child, has parent_id + offsets)
        └── → Export (share clip)
```

- Scenes are **maximum one level deep** — no grandchildren, enforced by validation
- Exports are **outside the content graph** — no tags, not searchable

---

## Scene Info Display

**Parent Scene** metadata panel shows:
- Own tags (full colour)
- Codec/resolution/duration badges (auto-detected)
- Markers list with start time, optional end time badge, title
- Clips list (if any) with timestamp ranges + titles

**Child Scene** metadata panel shows:
- Own tags (full colour)
- Inherited parent tags (muted/grey)
- "Clipped from: [Parent Title] ↗" provenance link
- Its own markers (if any)

---

## Export Flow

1. User clicks **Share** on a `SceneMarker` or clip `Scene`
2. Picks a preset
3. `ExportJob` enqueued via SolidQueue — runs ffmpeg asynchronously
4. User notified when ready → downloads file
5. Export file deletable after download — re-exportable any time from source

---

## Preview / VTT Generation

Markers generate:
- `.mp4` preview clip — duration is `end_offset_ms - start_offset_ms` when ranged, fallback 20 000 ms
- `.webp` animated thumbnail — duration capped at 5 000 ms
- VTT chapter track — uses correct start/end times when ranged

File names keyed on `start_offset_ms` (e.g. `142000.mp4`).

---

## Import / Export (JSON round-trip)

Marker JSON includes `end_offset_ms` conditionally so existing exports stay clean:

```ruby
marker_json = {
  title: marker.title,
  start_offset_ms: marker.start_offset_ms,
  tags: marker.tags.map(&:name)
}
marker_json[:end_offset_ms] = marker.end_offset_ms if marker.end_offset_ms.present?
```

---

## Key Constraints Summary

- Timestamps: **milliseconds integers** everywhere, no decimal seconds
- Tags: **flat only**, no hierarchy
- Scene nesting: **one level max** (parent → clips)
- Markers: default annotation — promote to child Scene deliberately and rarely
- Exports: transient, outside content graph, never become Scenes
- Video type is a **tag** not an enum
- Codec/resolution/duration are **columns + badges**, not tags
