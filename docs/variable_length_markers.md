# Variable-Length Markers (`end_seconds`)

## Context

Scene markers are currently point-in-time bookmarks — they have a `seconds` start time but no end time. Generated preview clips are hardcoded to 20 seconds regardless of what the marker actually covers, and the VTT chapter track uses identical start/end timestamps. Adding an optional `end_seconds` field makes markers genuine ranged annotations: the generated clip covers exactly the marked section, the chapter track has correct durations, and import/export round-trips preserve the range.

## Files to change

1. **New migration** — `db/migrate/<timestamp>_add_end_seconds_to_scene_markers.rb`
2. **`app/models/scene_marker.rb`** — optional validation
3. **`app/models/scene.rb`** — `chapter_vtt` method
4. **`lib/canister/tasks/generate_markers.rb`** — clip duration
5. **`lib/canister/tasks/import.rb`** — parse `end_seconds`
6. **`lib/canister/tasks/export.rb`** — serialize `end_seconds`
7. **`app/views/scenes/show.html.erb`** — display duration in marker list

---

## Step-by-step

### 1. Migration

```ruby
class AddEndSecondsToSceneMarkers < ActiveRecord::Migration[8.1]
  def change
    add_column :scene_markers, :end_seconds, :decimal
  end
end
```

Nullable — existing markers are unaffected.

---

### 2. Model: `app/models/scene_marker.rb`

Add an optional numericality validation after the existing `seconds` validation:

```ruby
validates :end_seconds, numericality: { greater_than: :seconds }, allow_nil: true
```

No other model changes needed — `stream_file_path` and `stream_preview_path` use `seconds.to_i` for the filename, which stays the same.

---

### 3. VTT chapters: `app/models/scene.rb`

Current `chapter_vtt` (lines 116–131) sets both start and end to `scene_marker.seconds` — technically invalid but browsers tolerate it. Update to use `end_seconds` when present:

```ruby
def chapter_vtt
  vtt = ["WEBVTT", ""]
  scene_markers.each do |m|
    end_time = m.end_seconds.present? ? m.end_seconds : m.seconds
    vtt.push("#{get_vtt_time(m.seconds)} --> #{get_vtt_time(end_time)}")
    vtt.push(m.title)
    vtt.push("")
  end
  vtt.join("\n")
end
```

`get_vtt_time` (private, already exists) is reused as-is.

---

### 4. Preview generation: `lib/canister/tasks/generate_markers.rb`

The `-t` flag in the ffmpeg command controls clip duration. Currently hardcoded to `20` for MP4 and `5` for WebP. Update to use `end_seconds - seconds` when available, falling back to the existing defaults:

```ruby
duration_mp4  = marker.end_seconds.present? ? (marker.end_seconds - marker.seconds).to_i : 20
duration_webp = marker.end_seconds.present? ? [(marker.end_seconds - marker.seconds).to_i, 5].min : 5
```

Then substitute `duration_mp4` and `duration_webp` for the hardcoded values in the two ffmpeg commands. File names stay `#{marker.seconds.to_i}.mp4` / `.webp` — no rename needed.

---

### 5. Import: `lib/canister/tasks/import.rb`

After `new_marker.seconds = marker['seconds']`, add:

```ruby
new_marker.end_seconds = marker['end_seconds'] if marker['end_seconds']
```

---

### 6. Export: `lib/canister/tasks/export.rb`

In the `marker_json` hash, add the field conditionally so existing exports stay clean:

```ruby
marker_json = {
  title: marker.title,
  seconds: marker.seconds,
  primary_tag: marker.primary_tag.name,
  tags: get_names(marker.tags)
}
marker_json[:end_seconds] = marker.end_seconds if marker.end_seconds.present?
json[:markers].push(marker_json)
```

---

### 7. View: `app/views/scenes/show.html.erb`

The marker list currently shows only the start time. Add a duration badge when `end_seconds` is set. Reuse the existing `format_duration` helper (`app/helpers/application_helper.rb`).

In the marker `<button>` block, after the start-time `<span>`, insert:

```erb
<% if marker.end_seconds.present? %>
  <span class="font-mono text-xs text-gray-400 shrink-0">
    → <%= format_duration(marker.end_seconds) %>
  </span>
<% end %>
```

The `data-seconds` attribute on the button stays as `marker.seconds.to_i` — clicking still seeks to the start of the marker.

---

## Verification

1. Run migration: `rails db:migrate`
2. Check schema: `db/schema.rb` should show `end_seconds decimal` on `scene_markers`
3. Console smoke test:
   ```ruby
   m = SceneMarker.first
   m.update!(end_seconds: m.seconds + 45)
   m.valid?   # => true
   m.scene.chapter_vtt  # should show different start/end times for this marker
   ```
4. Invalid range rejected:
   ```ruby
   m.update(end_seconds: m.seconds - 10)  # => validation error
   ```
5. Import round-trip: export a scene with a marker, add `end_seconds` to the JSON, re-import, confirm it persists.
6. View: load a scene with an `end_seconds` marker — confirm the `→ X:XX` badge appears beside the start time.
7. Generation: run `rails metadata:generate_markers` on a scene with a ranged marker and verify the `.mp4` clip length matches `end_seconds - seconds`.
