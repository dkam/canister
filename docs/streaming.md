# Video Streaming Architecture

## Streaming Formats

The app currently supports 2 video streaming formats via FFmpeg on-the-fly transcoding with hardware acceleration support.

### Progressive Streaming (Single File)

| Endpoint | Description | Codec | Scope |
|----------|-------------|-------|--------|
| `/stream` | Direct streaming (byte-range) | Original | Implemented |
| `/stream.mp4` | MP4 container (smart codec selection) | H.264 (copy) or transcoded | Implemented |
| `/stream.webm` | WebM container | VP9 | Planned |
| `/stream.mkv` | MKV container | Original + Opus audio | Planned |

### Adaptive Bitrate Streaming

| Endpoint | Description | Segments | Scope |
|----------|-------------|----------|--------|
| `/stream.m3u8` | **HLS** (HTTP Live Streaming) | MPEG-TS (2-second chunks) | Implemented |
| `/stream.mpd` | **MPEG-DASH** (Dynamic Adaptive Streaming) | WebM video/audio segments (2-second chunks) | Planned |

### Features

- On-the-fly FFmpeg transcoding
- Hardware acceleration support (GPU encoders)
- Smart codec selection (copy when possible, transcode when needed)
- Seek support with timestamp parameter (`?start=`) for progressive streams
- Resolution and bitrate control via `resolution` query parameter (planned)

---

## How a Format Is Chosen

### Backend: Building Stream List

The backend generates an ordered list of available stream endpoints for each video based on file's codec metadata. It does not pick one format — it offers everything that's valid and lets the frontend decide.

**Audio codec compatibility** gates which endpoints are offered:

| Container | Allowed audio codecs |
|-----------|----------------------|
| MP4 | AAC, MP3 |
| WebM | Opus, Vorbis |
| MKV | Never offered as direct (browsers don't support MKV) |

The direct stream (`/stream`) is only included if:
1. Video codec is valid HTML5 (H.264, H.265, VP8, VP9, AV1)
2. Audio codec matches container (AAC/MP3 for MP4, Opus/Vorbis for WebM)
3. Container is browser-native (MP4, WebM, MOV, M4V)

MP4 progressive stream (`/stream.mp4`) includes smart codec flags:
- `video_copy: true` if source is H.264
- `audio_transcode: true` if source audio is Opus/Vorbis (must transcode to AAC)

**Example stream configs:**

For MKV with H.264 + Opus:
```json
[
  {
    "kind": "progressive",
    "mime_type": "video/mp4",
    "label": "MP4 (H.264 copy) AAC transcode",
    "seek_mode": "timestamp",
    "video_copy": true,
    "audio_transcode": true
  }
]
```

For MP4 with H.264 + AAC:
```json
[
  {
    "kind": "direct",
    "mime_type": "video/mp4",
    "label": "Direct stream",
    "seek_mode": "byte_range",
    "video_copy": true,
    "audio_transcode": false
  },
  {
    "kind": "progressive",
    "mime_type": "video/mp4",
    "label": "MP4 (H.264 copy)",
    "seek_mode": "timestamp",
    "video_copy": true,
    "audio_transcode": false
  }
]
```

The resulting list — each entry with a URL, MIME type, label, and codec flags — is returned to the client via the `build_stream_endpoints` method in `ScenesController`.

### FFmpeg Command Selection

The `stream_mp4` controller uses the stream config to build smart FFmpeg commands:

| Video | Audio | FFmpeg Command |
|--------|--------|---------------|
| H.264 | AAC/MP3 | `-c:v copy -c:a copy` (fastest) |
| H.264 | Opus/Vorbis | `-c:v copy -ac 2` (fast: video copy, audio remux to AAC) |
| VP9/AV1 | Any | `-c:v libx264 -preset veryfast -crf 23 -ac 2` (slow: full transcode) |

### Frontend: Trying Sources in Order

The player receives the full list and works through it:

1. **Play first source** — usually direct stream
2. **Auto-fallback** — if playback fails with `MEDIA_ERR_SRC_NOT_SUPPORTED` or `MEDIA_ERR_DECODE`, player moves to the next source
3. **User override** — a source selector dropdown lets user force a specific format (Video.js feature)

### Seeking

Direct streaming (`/stream`) uses byte-range requests for seeking.

Progressive streaming (`/stream.mp4`) requires a `?start=<seconds>` parameter for seeking — the FFmpeg process restarts at that offset.

---

## Summary

```
Video codecs in DB
    ↓
Backend validates audio codec against container format
    ↓
Generates ordered list: [direct, progressive] × resolutions
    ↓
Frontend receives stream configs via JSON
    ↓
Video.js tries first source (direct stream if available)
    ↓
Codec error? → auto-try next source in list
    ↓
User can manually override at any time
```

---

## Progressive Transcode Lifecycle

Progressive transcode (`/stream.mp4`) uses per-request FFmpeg processes with automatic cleanup.

### Request Flow

**1. Initial load:**
```
Browser → GET /scenes/5/stream.mp4?start=0
FFmpeg starts → -ss 0 -i input.mkv -c:v copy -ac 2 -f mp4 pipe:1
              → transcoding from 0 to end
```

**Rails implementation:**
- `app/controllers/scenes/streams_controller.rb:25-58` — `stream_mp4` action builds command from stream config
- `app/controllers/scenes/streams_controller.rb:68-85` — `build_ffmpeg_command` constructs FFmpeg args based on codec flags
- `app/models/concerns/streamable.rb:10-23` — `available_streams` provides stream configuration

**2. Seek to unbuffered position:**
```
Browser closes connection → Open3.popen3 returns EPIPE/ECONNRESET
FFmpeg killed automatically (process dies when pipe closes)
Browser → GET /scenes/5/stream.mp4?start=45.5 (NEW FFmpeg process)
```

**Rails implementation:**
- `app/controllers/scenes/streams_controller.rb:33` — `stream_mp4` logs debug info for each request
- `app/controllers/scenes/streams_controller.rb:48-52` — Open3.popen3 with stderr consumer thread prevents deadlock

**3. Browser pauses:**
```
FFmpeg: Open3.popen3(...stdout...)
       ↓
    stdout pipe buffers FFmpeg output
       ↓
    TCP connection buffers network data
       ↓
    Browser stops reading
       ↓
    TCP buffer fills → network write blocks
    Pipe buffer fills → FFmpeg blocks on write
```

FFmpeg **waits** (paused), consuming memory but no wasted network traffic. Backpressure is natural — FFmpeg can't write until browser reads again.

**Rails implementation:**
- `app/controllers/scenes/streams_controller.rb:49-52` — Thread consumes stderr to prevent pipe deadlock
- `app/controllers/scenes/streams_controller.rb:55-56` — `until stdout.eof?` loop blocks on backpressure

**4. Browser resumes:**
```
Browser reads → TCP buffer drains → pipe buffer drains → FFmpeg unblocks
Transcoding continues
```

### Data Volume

Each request sends **data from start time to end of video** (or until disconnect):

```
Request: /stream.mp4?start=45.5
Video duration: 4:19 (259 seconds)
Data sent: 259 - 45.5 = 213.5 seconds of video
```

- No `Content-Length` header (chunked transfer)
- Response ends when: video finishes OR browser closes connection

**Rails implementation:**
- `app/controllers/scenes/streams_controller.rb:43-44` — Sets `Cache-Control: no-store` and MIME type, no `Content-Length`

### FFmpeg Process Lifecycle

| Scenario | FFmpeg Behavior |
|----------|----------------|
| Browser seeks to new position | Old FFmpeg killed, new one spawned |
| Browser pauses | FFmpeg blocks on full pipe (backpressure) |
| Browser resumes | FFmpeg unblocks, continues transcoding |
| Browser stops/closes tab | FFmpeg killed (SIGPIPE from closed pipe) |
| Error during transcode | Process exits, error logged in ensure block |

**Rails implementation:**
- `app/controllers/scenes/streams_controller.rb:35-37` — Rescue `ClientDisconnected`, `EPIPE` gracefully
- `app/controllers/scenes/streams_controller.rb:39-40` — Rescue and log other errors
- `app/controllers/scenes/streams_controller.rb:43-59` — Ensure block closes response.stream

### Format Differences

Progressive MP4 streaming uses smart codec selection:

| Source Video | Source Audio | MP4 Stream | Operation |
|---------------|---------------|----------------|------------|
| H.264 | AAC/MP3 | H.264 + AAC | Copy (fastest) |
| H.264 | Opus/Vorbis | H.264 + AAC | Video copy + audio transcode (fast) |
| VP9/AV1 | Any | H.264 + AAC | Full transcode (slow) |

**Rails implementation:**
- `app/models/concerns/streamable.rb:46-67` — `build_mp4_stream` determines copy vs transcode flags
- `app/controllers/scenes/streams_controller.rb:68-85` — `build_ffmpeg_command` constructs FFmpeg args accordingly

---

## Configuration

| Variable | Default | Description |
|---|---|---|
| `TRANSCODE_PATH` | `{root}/transcodes` | Pre-generated transcode files |
| `FFMPEG_LOGGER_LEVEL` | `WARN` | FFmpeg output logging level |

---

## Implementation Files

| File | Purpose |
|------|---------|
| `app/models/concerns/streamable.rb` | Stream configuration generation with codec flags |
| `app/controllers/scenes/streams_controller.rb` | Direct streaming, progressive MP4, HLS manifest + segment serving |
| `app/services/hls/stream_manager.rb` | Singleton orchestrator — delegates to Primary, Quantum, Cache, Manifest |
| `app/services/hls/primary_process.rb` | Primary FFmpeg lifecycle — runs to completion, incremental duration saving |
| `app/services/hls/quantum_process.rb` | Short-lived quantum FFmpeg processes for seek/on-demand playback |
| `app/services/hls/ffmpeg_command.rb` | FFmpeg command building for both primary and quantum modes |
| `app/services/hls/manifest_builder.rb` | Four-tier manifest generation |
| `app/services/hls/segment_cache.rb` | LRU cache, eviction, disk operations |
| `app/controllers/scenes_controller.rb` | Stream endpoint URL building |
| `config/routes.rb` | Route definitions |

---

## Testing Scenarios

| Source File | Video | Audio | Expected MP4 Stream |
|--------------|--------|--------|---------------------|
| MP4, H.264 + AAC | H.264 | AAC | Direct + MP4 copy (fastest) |
| MP4, H.264 + MP3 | H.264 | MP3 | Direct + MP4 copy (fastest) |
| WebM, VP9 + Opus | VP9 | Opus | MP4 full transcode (slow) |
| MKV, H.264 + Opus | H.264 | Opus | MP4: video copy, audio transcode (fast) |
| MKV, AV1 + Vorbis | AV1 | Vorbis | MP4 full transcode (slow) |

---

## HLS Streaming Architecture

Two complementary FFmpeg modes — **Primary** and **Quantum** — work together to provide HLS streaming with accurate manifests. Primary produces seamless playback (continuous encode). Quantum provides instant seek but may have micro-glitches at boundaries for transcoded streams (not an issue for remux).

### Concepts

**Primary FFmpeg** — a single long-running process per scene that starts at segment 0 and runs to completion. It writes the canonical `manifest.m3u8` progressively and saves segment durations incrementally to the database. The primary is never killed — it always runs to completion. If it crashes or the server restarts, it resumes from the last stored segment using exact timestamps. For remux at ~10x realtime, a 2-hour video finishes in ~12 minutes.

**Quantum FFmpeg** — a short-lived, self-terminating process spawned on demand for seek playback and prefetch. Each quantum covers a fixed range of segments and exits naturally via `-t`. Quantums provide immediate playback anywhere in the video. Once all durations are stored from a completed primary run, quantums are all that's needed for all future plays — the primary doesn't need to run again.

### Constants (`Hls::StreamManager`)

| Constant | Value | Purpose |
|---|---|---|
| `SEGMENT_DURATION` | 2s | Seconds per `.ts` segment |
| `SEGMENT_WAIT_TIMEOUT` | 15s | Max seconds to wait for segment before returning 404 |
| `MAX_SEGMENT_GAP` | 5 | Spawn quantum if request is >5 segments ahead of primary |
| `PREFETCH_HORIZON` | 10 | Preemptively spawn quantum when fewer than 10 segments ahead on disk |
| `SEGMENTS_PER_QUANTUM` | 10 | Segments per quantum (20 seconds of content) |
| `KEEP_FIRST_SEGMENTS` | 15 | Always preserve segments 0–14 during cache eviction |
| `MAX_CACHE_SIZE` | 5GB | LRU eviction threshold (override with `HLS_MAX_CACHE_SIZE_GB` env var) |

### Stored Segment Durations

Durations are stored in `Scene#hls_segment_durations` as a hash keyed by segment index (string keys in JSON): `{"0" => 1.999, "1" => 2.001, ...}`. This enables:

- **Incremental saving** — durations are persisted on every monitor tick as the primary generates segments. If the primary crashes at segment 500, durations 0-499 are already in the DB.
- **Resumable primary** — on restart, the primary resumes from the last stored segment with `-ss` computed as the sum of all stored durations (exact timestamp).
- **Exact quantum seeks** — quantum `-ss` is computed by summing stored durations for all segments before its start point.
- **Completion detection** — `durations.size >= total_segments` means the primary has finished. No separate boolean needed.

Both remux and transcode streams save durations (no `video_copy` gate).

### Request Flow

**1. Manifest request (`stream_hls`) — four-tier resolution:**

```
1. manifest.m3u8 on disk with #EXT-X-ENDLIST (primary finished) → rewrite segment URLs
2. manifest.m3u8 on disk without #EXT-X-ENDLIST (primary running) → rewrite segment URLs
3. hls_segment_durations hash in DB → reconstruct exact manifest from stored values
4. No data (never played) → serve estimated uniform-2s manifest, start primary
```

**2. Segment request (`stream_hls_segment`):**

```
Browser → GET /scenes/{id}/stream_hls/42
  ├─ Segment on disk → prefetch_ahead(), serve immediately
  └─ Not on disk:
       ├─ Primary running and close (within MAX_SEGMENT_GAP) → wait on CV
       └─ Otherwise → spawn quantum, wait on CV
           └─ Timeout (15s) → 404
```

**3. Prefetch (runs on every cache-hit segment request):**

```
Count consecutive segments ahead of current request
  └─ Fewer than PREFETCH_HORIZON (10) segments ahead?
       └─ Primary not running? → spawn quantum for first missing segment's range
```

This prevents stalls during sequential playback — the quantum starts generating the next batch of segments while the player still has ~20 seconds of buffered content.

**4. Monitor thread (runs every 200ms):**

```
For each primary with a PID (including just-exited):
  ├─ Rename completed dotfiles (.N.ts → N.ts), broadcast CV
  ├─ Detect natural exit → final rename, save durations from manifest
  └─ Incremental duration saving on each tick (if new segments renamed)

For each quantum:
  ├─ Rename completed dotfiles, broadcast CV
  ├─ Detect natural exit → final rename
  └─ Clean up 0-byte dotfiles (only after FFmpeg exits)

After stream checks:
  └─ LRU eviction (skipping scenes with active primary)
```

### Dotfile Pattern

Both primary (`-f hls`) and quantum (`-f segment`) write segments as dotfiles (`.N.ts`). The monitor renames `.N.ts → N.ts` once the *next* dotfile appears, guaranteeing the segment is complete before serving.

```
FFmpeg writing:  .0.ts  .1.ts  .2.ts  .3.ts ...
After rename:     0.ts   1.ts   2.ts          ← .3.ts still being written
```

**Primary** uses `each_cons(2)` — safe because primary writes sequentially and the last dotfile is renamed on exit detection.

**Quantum** uses `each_cons(2)` while running, then renames all remaining non-zero dotfiles on exit. The 0-byte cleanup only runs after FFmpeg exits — cleaning up 0-byte files while FFmpeg is running races with file creation (FFmpeg creates a 0-byte file, monitor deletes it, FFmpeg writes to the now-deleted inode, segment is lost).

### Primary Lifecycle

**First play:**
```
1. ensure_running() → primary starts at segment 0
2. Primary writes manifest.m3u8 + dotfile segments (.N.ts)
3. Monitor renames dotfiles, saves durations incrementally to DB
4. Primary finishes → complete manifest on disk, all durations in DB
```

**Resumable:** If `hls_segment_durations` exists but is incomplete, the primary resumes from the last stored segment with `-ss` = sum of all stored durations. This is an exact timestamp — no keyframe mismatch.

**Complete durations:** If `hls_segment_durations.size >= total_segments`, the primary skips entirely — all future plays use quantum only.

### Quantum Lifecycle

Segments are grouped into fixed, non-overlapping windows:
```
Quantum size: 20 seconds = 10 segments (at 2s/segment)
Boundaries:   0s, 20s, 40s, 60s, ... (segment 0, 10, 20, 30, ...)
quantum_start = (segment_idx / SEGMENTS_PER_QUANTUM) * SEGMENTS_PER_QUANTUM
```

**Guards before spawning:**
1. `running_for?` — don't spawn if a live quantum already covers this segment
2. `dest.exist?` — don't spawn if the requested segment already exists on disk

**Primary always wins:** when primary's monitor renames a segment, it atomically overwrites any quantum-generated segment at that position. Primary segments are canonical (continuous boundaries from segment 0).

### Quantum `-ss` Timestamp Modes

| Mode | When | `-ss` value | Boundary quality |
|---|---|---|---|
| Exact | Stored durations exist for segments 0 through `quantum_start - 1` | Sum of stored durations | Identical to primary — no discontinuity |
| Estimated | No stored durations for the full range | `quantum_start * SEGMENT_DURATION` | Approximate — minor keyframe mismatch (remux only) |

For transcode streams (forced keyframes at 2s), both modes produce identical results — the distinction only matters for remux.

### Segment Duration Behaviour

**Transcode streams** (`video_copy: false`): Forced keyframes at 2s intervals (`-force_key_frames expr:gte(t,n_forced*2)`) produce uniform segment durations. All segments are exactly 2.000s (except the last).

**Remux streams** (`video_copy: true`): `-hls_flags split_by_time` tracks **absolute** split targets (2s, 4s, 6s, ...) and splits at the next keyframe at or after each target:

```
Keyframes at:  0    2.3   4.5   6.1   8.7   ...
Target splits: 2s   4s    6s    8s    10s   ...
Actual splits: 2.3  4.5   6.1   8.7   ...
Segment durs:  2.3  2.2   1.6   2.6   ...
```

Drift is bounded by keyframe spacing, and the average converges toward 2s. The estimated uniform-2s manifest is a reasonable approximation for first play.

### Cache Eviction

Segments are stored in `tmp/hls/{scene_id}/`. When total size exceeds `MAX_CACHE_SIZE`, the monitor evicts least-recently-accessed scenes, preserving segments 0–14 for fast restart. **Scenes with an active primary are never evicted** — this prevents the cache cleaner from deleting early segments while the primary is still running toward the end.

### Seek Behaviour

| Scenario | Behaviour |
|---|---|
| Backward seek, segment cached | Instant cache hit |
| Backward seek, uncached | Quantum spawned, primary continues |
| Forward seek, cached | Instant cache hit |
| Forward seek, uncached | Quantum spawned, primary continues |
| Sequential playback, segments ahead | Served from disk; prefetch spawns quantum when running low |
| Pause | Primary continues to completion. No kills. |
| Close tab / server idle | Primary continues to completion (intentional — captures all durations) |
| Continuous playback (transcode) | Player may outpace primary; quantum fills gaps via prefetch |
| Two tabs, same video | One primary; quantums shared via filesystem. Duplicate prevention within worker. |

### Multiple Puma Workers

Each worker has its own `StreamManager` singleton. Coordination happens through the filesystem — if another worker's FFmpeg already generated a segment, the `.ts` file exists and is served immediately. The primary's incremental duration saving uses `update_column` which is atomic per row in SQLite.

### Edge Cases

- **Last quantum of a video** — may be shorter than 20s. FFmpeg hits EOF and exits naturally before `-t` expires.
- **FFmpeg error mid-quantum** — monitor detects exit, does final dotfile rename. If requested segment wasn't produced, `request_segment` times out (15s) → 404. Player retry spawns a fresh quantum.
- **Multiple seeks in quick succession** — each spawns a quantum for its target range. Multiple quantums run concurrently for non-overlapping ranges.
- **Cache eviction with partial durations** — quantums within the known duration range use exact timestamps; those beyond use estimated. Next primary run fills in remaining durations.
- **Server restart mid-primary** — durations already saved incrementally. Next play resumes primary from last stored segment, or if complete, uses quantum only.

---

## FFmpeg `-f segment` vs `-f hls` — Pitfalls

If you're implementing a similar system, these are the critical differences between the HLS muxer and the segment muxer that will bite you:

### `-f segment` does not split on time by default

The segment muxer only splits on **keyframes**. If your source has keyframes every 6 seconds, you get one 6-second segment instead of three 2-second segments. This is different from `-f hls -hls_flags split_by_time` which forces time-based splits.

**Fix:** Add `-break_non_keyframes 1` to allow splitting at non-keyframe points:

```
# HLS muxer (primary):
-f hls -hls_flags split_by_time -hls_time 2

# Segment muxer (quantum) — equivalent:
-f segment -segment_time 2 -break_non_keyframes 1
```

Without `-break_non_keyframes 1`, you will get oversized segments and missing segment numbers.

### `-copyts` breaks `-f segment`

With `-copyts`, output timestamps preserve the input seek position (e.g. `-ss 40` produces timestamps starting at 40s). The segment muxer calculates split points from these timestamps, which misaligns with `-segment_time` and `-segment_start_number`. FFmpeg may produce far fewer segments than expected, or exit immediately.

**Fix:** Do not use `-copyts` with `-f segment`. Use `-reset_timestamps 1` instead — each segment gets PTS starting at 0, which is clean for HLS playback (the manifest's `#EXTINF` controls timing, not internal PTS).

```
# BAD: quantum with -copyts — produces wrong number of segments
-ss 40 -i input -copyts -f segment -segment_start_number 20 -segment_time 2

# GOOD: quantum with reset_timestamps
-ss 40 -i input -f segment -segment_start_number 20 -segment_time 2 -reset_timestamps 1
```

Note: `-copyts` works fine with `-f hls` — the HLS muxer handles timestamp offsets correctly. It's only `-f segment` that breaks.

### `-output_ts_offset` also breaks `-f segment`

Similar to `-copyts`, `-output_ts_offset` shifts all output timestamps which confuses the segment muxer's split-point calculation. A 20-second quantum may produce 1 segment instead of 10.

**Fix:** Don't use `-output_ts_offset` with `-f segment`. If you need continuous timestamps across segments, use `-f hls` (primary) for the canonical run. For quantum, `reset_timestamps` is sufficient — HLS players use manifest timing, not internal PTS.

### 0-byte dotfile race condition

With the dotfile rename pattern (`.N.ts` → `N.ts`), be careful about cleaning up 0-byte files:

```
1. FFmpeg creates .12.ts (0 bytes — just opened for writing)
2. Monitor tick runs, sees 0-byte .12.ts, deletes it
3. FFmpeg writes to the deleted inode (file descriptor still valid)
4. FFmpeg closes file — data written to deleted inode, lost forever
5. Segment 12 is permanently missing
```

**Fix:** Only delete 0-byte dotfiles **after FFmpeg has exited**. While FFmpeg is running, a 0-byte file may be freshly created and about to receive data.

### Monitor must track processes with PID, not just alive processes

The monitor loop must iterate over all processes that have a non-nil PID, not just those confirmed alive. If you filter to `process_alive?` first, a process that exits between monitor ticks will never have its exit detected — its dotfiles will never get the final rename, and its durations will never be saved.

```ruby
# BAD: misses processes that exited between ticks
@primary.active_scene_ids.each { |id| @primary.monitor_tick(id) }

# GOOD: includes just-exited processes so exit detection runs
@primary.scene_ids_with_pid.each { |id| @primary.monitor_tick(id) }
```

### Quantum segment deduplication

Without guards, the same quantum range can be spawned repeatedly:
1. Quantum 0-9 runs and exits
2. Player requests segment in same range
3. `running_for?` returns false (process exited)
4. New quantum spawns, overwrites existing segments

For identical ranges this wastes resources. For overlapping ranges from different seek points, it corrupts content (segment N gets content from a different timestamp).

**Fix:** Before spawning, check if the requested segment already exists as a final file on disk:
```ruby
return if output_dir.join("#{segment_idx}.ts").exist?
```

### Audio preroll at quantum seek boundaries

When `-ss` before `-i` seeks to the nearest keyframe, the first segment of each quantum gets **extra audio frames** before the video starts. Audio decodes precisely from the keyframe position, but video can only start from a keyframe — so the segment muxer receives audio preroll that doesn't match the video.

Measured on an AV1 → H.264 transcode (2-second segment target):

| Quantum boundary segment | Audio duration | Video duration | Preroll |
|--------------------------|---------------|----------------|---------|
| Segment 0 (no seek)     | 1.9s          | 2.0s           | None    |
| Segment 10 (ss=20)      | 1.9s          | 2.0s           | ~0s (close keyframe) |
| Segment 20 (ss=40)      | **4.0s**      | 2.0s           | **~2.0s** |
| Segment 30 (ss=60)      | **2.7s**      | 2.0s           | **~0.7s** |
| Segment 50 (ss=100)     | **6.9s**      | 2.0s           | **~4.9s** |

The preroll amount depends on keyframe distance at the seek point — unpredictable and varies per source.

**Fix:** Start each quantum 1 segment earlier than the requested range. The first segment absorbs the seek preroll as a throwaway. The rename filter already excludes segments outside `start_segment..end_segment`, so the preroll segment is never served. The previous quantum's clean segment (or no segment, for the very first quantum starting at 0) is preserved on disk by the `next if dest.exist?` guard.

```ruby
# Start 1 segment earlier to absorb audio preroll
ffmpeg_start = [quantum_start - 1, 0].max
preroll_extra = (quantum_start - ffmpeg_start) * SEGMENT_DURATION
start_time = compute_start_time(scene, ffmpeg_start)

cmd = FfmpegCommand.quantum(
  from_segment: ffmpeg_start,       # FFmpeg numbers from here
  start_time: start_time,           # seek to the earlier position
  duration: QUANTUM_DURATION + preroll_extra  # slightly longer to compensate
)

# QuantumStream tracks start_segment = quantum_start (not ffmpeg_start)
# so rename_dotfiles naturally excludes the preroll segment.
# On exit, cleanup_preroll_dotfile deletes the orphan.
```

### Quantum boundary micro-glitches (transcode only)

Even with the preroll fix above, quantum boundaries produce **audible micro-glitches** on transcoded streams (AV1, VP9, etc. being transcoded to H.264). Each quantum is an independent FFmpeg encode — the encoder state (motion estimation history, audio codec state, bitstream buffer) is different at the start of each quantum vs what a continuous encode would produce. Two independent encodes of the same source at the same timestamp produce slightly different bitstreams.

This is not an issue for **remux** streams (`-c:v copy -c:a copy`) where the original bitstream is preserved unchanged.

**Status:** Not fully solved. Approaches tried and their outcomes:

| Approach | Outcome |
|----------|---------|
| `-output_ts_offset` to shift quantum timestamps | Broke segment muxer — produced 1 segment instead of 10 |
| `-copyts` to preserve source timestamps | Broke segment muxer entirely (see above) |
| `-reset_timestamps 1` per segment | Fixed segment numbering but doesn't help with codec discontinuity |
| Preroll absorption (start 1 segment early) | Fixes audio preroll, but not encoder state discontinuity |

**Correct solution:** The primary process must run for transcoded streams. Primary runs continuously from segment 0, so all boundaries are natural and seamless. Quantum is a stopgap for immediate playback while primary catches up. If the primary has previously completed but segments were evicted from cache, the primary must re-run (not rely on quantum-only regeneration).

Key insight: stored `hls_segment_durations` alone don't mean the primary is "complete" — the manifest file must also exist on disk. If the cache was evicted (no manifest), re-run the primary from scratch even if durations are stored. The stored durations remain useful for exact quantum `-ss` timestamps while the primary catches up.

---

## Future Enhancements

- WebM progressive streaming (`/stream.webm`) — for VP9 sources
- MPEG-DASH (`/stream.mpd`) — adaptive streaming
- Resolution variants (4K, 1080p, 720p, 480p, 240p)
- Hardware acceleration — GPU encoder support
