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
| `app/lib/canister/stream_manager.rb` | HLS FFmpeg lifecycle singleton (buffer, seek, LRU eviction) |
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

## HLS Streaming Lifecycle

HLS uses a kill-and-restart pattern rather than running FFmpeg to completion. FFmpeg runs ahead by a fixed buffer, gets killed when the buffer is full, and restarts on demand when the viewer needs uncached segments.

### Constants (`Canister::StreamManager`)

| Constant | Value | Purpose |
|---|---|---|
| `SEGMENT_DURATION` | 2s | Seconds per `.ts` segment |
| `MAX_SEGMENT_BUFFER` | 15 | Kill FFmpeg when 15 segments ahead of last requested (30s runway) |
| `MAX_SEGMENT_GAP` | 5 | Restart if request is >5 segments ahead of highest generated |
| `MAX_IDLE_TIME` | 30s | Kill FFmpeg after 30s with no segment requests |
| `KEEP_FIRST_SEGMENTS` | 15 | Always preserve segments 0–14 in cache (fast start on revisit) |
| `MAX_CACHE_SIZE` | 5GB | LRU eviction threshold (override with `HLS_MAX_CACHE_SIZE_GB` env var) |

### Request Flow

**1. Manifest request (`stream_hls`) — three-tier resolution:**

```
1. hls_segment_durations stored in DB (remux streams only) → serve immediately
   └─ If segments not on disk: tell StreamManager to ensure FFmpeg is running
2. manifest.m3u8 exists in tmp/hls/{id}/ → rewrite segment filenames to app URLs
3. Fresh start → StreamManager starts FFmpeg, serve calculated manifest (uniform 2s durations)
```

**2. Segment request (`stream_hls_segment`):**

```
Browser → GET /scenes/{id}/stream_hls/42
StreamManager checks disk → segment exists? → send_file immediately (cache hit)
                          → no?
                              FFmpeg running?
                                no  → start FFmpeg at segment 42
                                yes → gap too large? → kill, restart at 42
                                    → otherwise update last_requested, wait
                          → wait on ConditionVariable (monitor broadcasts on each rename)
                          → segment appears → send_file
                          → timeout (15s) → 404
```

**3. Monitor thread (runs every 200ms):**

```
For each active stream:
  ├─ Rename completed dotfiles (.N.ts → N.ts), broadcast ConditionVariable
  ├─ Detect dead FFmpeg → final rename, save timestamps if full run from segment 0
  ├─ Buffer full? (15 consecutive segments from last_requested) → kill FFmpeg
  └─ Idle? (30s no requests) → kill FFmpeg

After stream checks:
  └─ LRU eviction: remove segments beyond first 15 from least-recently-used scenes
     until total tmp/hls/ size is under MAX_CACHE_SIZE
```

### Dotfile Pattern

FFmpeg writes segments as `.N.ts` (dotfiles) while they are open for writing. The monitor renames `.N.ts → N.ts` once the *next* dotfile appears, guaranteeing the segment is complete before it is served.

```
FFmpeg writing:  .0.ts  .1.ts  .2.ts  .3.ts ...
After rename:     0.ts   1.ts   2.ts          ← 3 is still open, not renamed yet
```

### Sequence Diagrams

**Happy path: play, pause, resume**

```
Browser              Controller              StreamManager              FFmpeg
   |                     |                        |                        |
   |-- GET segment 0 --> |                        |                        |
   |                     |-- request_segment(0) ->|                        |
   |                     |                        |-- spawn ffmpeg at 0 -->|
   |                     |  wait on CV ...        |                        |-- writes .0.ts, .1.ts...
   |                     |                        |<-- monitor renames, broadcasts CV
   |<-- serve 0.ts ------|                        |                        |
   |                     |                        |                        |
   |-- GET segment 1 --> |                        |                        |
   |                     |-- request_segment(1) ->|  (already running)     |
   |                     |<- 1.ts exists (hit)    |                        |
   |<-- serve 1.ts ------|                        |                        |
   |                     |                        |                        |
   | ... segments 2-15 served from cache ...      |                        |
   |                     |                        |                        |
   | (user pauses)       |                        |-- monitor: buffer full |
   |                     |                        |-- SIGTERM ffmpeg       |
   |                     |                        |                  (dies)|
   |                     |                        |                        |
   | (user resumes)      |                        |                        |
   |-- GET segment 16 -->|                        |                        |
   |                     |-- request_segment(16)->|                        |
   |                     |                        |-- spawn ffmpeg at 16 ->|
   |                     |  wait on CV ...        |                        |-- writes .16.ts...
   |<-- serve 16.ts -----|                        |                        |
```

**Seek forward (beyond gap)**

```
Browser              Controller              StreamManager              FFmpeg
   |                     |                        |                        |
   | (playing segment 5) |                        |  (ffmpeg at segment 8) |
   |                     |                        |                        |
   | (seek to 1:30:00 = segment 2700)             |                        |
   |-- GET segment 2700->|                        |                        |
   |                     |-- request_segment(2700)|                        |
   |                     |                        |  2700 > 8+5 → gap!     |
   |                     |                        |-- SIGTERM old ffmpeg   |
   |                     |                        |-- spawn at 2700 ------>|
   |                     |  wait on CV ...        |                        |-- writes .2700.ts...
   |<-- serve 2700.ts ---|                        |                        |
```

**Idle timeout**

```
Browser              Controller              StreamManager              FFmpeg
   |                     |                        |                        |
   | (tab closed)        |                        |  (ffmpeg running)      |
   |                     |                        |                        |
   |                     |                        |  30s no requests       |
   |                     |                        |-- SIGTERM ffmpeg       |
   |                     |                        |  (files kept on disk)  |
```

### Seek Behaviour

| Scenario | Behaviour |
|---|---|
| Backward seek, segment cached | Instant — cache hit, no FFmpeg interaction |
| Backward seek, segment not cached | Kill + restart at seek position (~1–2s pause) |
| Forward seek within buffer | Cache hit |
| Forward seek beyond `MAX_SEGMENT_GAP` | Kill + restart at seek position |
| Pause (buffer fills) | Monitor kills FFmpeg; restarts on next segment request |
| Close tab / idle 30s | Monitor kills FFmpeg |
| Two tabs, same video | One FFmpeg process; both viewers share cached segments |

### Multiple Puma Workers

Each worker has its own `StreamManager` instance and its own PID tracking. Coordination happens through the filesystem — if another worker's FFmpeg already generated a segment, the `.ts` file exists and is served immediately. Duplicate spawns are prevented within a worker; two workers may briefly both spawn FFmpeg for the same scene, but the second one will be killed promptly by its own buffer-full check.

### Segment Duration Behaviour (Remux Streams)

For transcoded streams, forced keyframes at 2s intervals produce uniform segment durations. This section only applies to remux (`video_copy: true`).

FFmpeg uses `-hls_time 2 -hls_flags split_by_time`. The `split_by_time` flag is critical — it makes FFmpeg track **absolute** split targets from the stream start (2s, 4s, 6s, ...) and split at the next keyframe at or after each target. This is different from the default behaviour (relative timing, where each segment is at least `hls_time` after the previous split).

```
Keyframes at:  0    2.3   4.5   6.1   8.7   ...
Target splits: 2s   4s    6s    8s    10s   ...
Actual splits: 2.3  4.5   6.1   8.7   ...
Segment durs:  2.3  2.2   1.6   2.6   ...
                          ^^^
                    shorter than 2s — compensating for prior overshoot
```

Because targets are absolute, segments can be both shorter and longer than 2s. When one segment overshoots its target significantly, the next segment is shorter to compensate. Drift is bounded by keyframe spacing (not compounding), and the average converges toward 2s over time. This means the calculated uniform-2s manifest is a reasonable approximation, with seek position error bounded to at most one keyframe interval at any point.

### Stored Segment Durations

For remux streams, after a **full run from segment 0**, the actual `#EXTINF` durations are parsed from `manifest.m3u8` and stored in `Scene#hls_segment_durations`. Subsequent plays serve the accurate manifest immediately without waiting for FFmpeg.

Durations are **not** saved for partial runs (seeks) because the segment boundaries shift with each restart, making stored values meaningless for other start positions.

### Boundary Discontinuities

Every time FFmpeg is killed and restarted (buffer full, seek), the new invocation seeks to the nearest keyframe at or before the target timestamp. This keyframe may not align with where the previous invocation's last segment ended — producing a small overlap or gap at the boundary. For the current implementation with a 30-second buffer, this discontinuity occurs approximately every 30 seconds during continuous remux playback (FFmpeg fills the buffer in ~3s, gets killed, player catches up in ~27s, restart). HLS players tolerate these discontinuities well — they are inherent to any restart-based HLS system and common in live streams.

### Cache Eviction

Segments are stored in `tmp/hls/{scene_id}/`. When total size exceeds `MAX_CACHE_SIZE`, the monitor evicts least-recently-accessed scenes, preserving segments 0–14 (`KEEP_FIRST_SEGMENTS`) for fast restart. Scenes with active FFmpeg processes are never evicted.

---

## Primary + Quantum FFmpeg

Two complementary FFmpeg modes work together to provide seamless HLS with accurate manifests.

### Concepts

**Primary FFmpeg** — a single long-running process per scene that starts at segment 0 and runs to completion. It writes the canonical `manifest.m3u8` progressively as it generates segments. The primary is the source of truth: its segments have continuous, unbroken boundaries from the start of the video, and its manifest contains exact `#EXTINF` durations for every segment. The primary is never killed during normal operation — only on idle timeout (tab closed, 30s no requests) or server shutdown.

**Quantum FFmpeg** — a short-lived process spawned on demand for seeks to uncached positions. Each quantum covers a fixed range of segments and self-terminates via `-t`. Quantums provide immediate playback while the primary is still catching up. Quantum FFmpeg must **not** write a manifest file — it only produces `.ts` segments. The primary's manifest is the single source of truth.

### Quantum Design

Segments are grouped into fixed, non-overlapping windows aligned to quantum boundaries from the start of the video:

```
Quantum size: 20 seconds = 10 segments (at 2s/segment)
Boundaries:   0s, 20s, 40s, 60s, ... (segment 0, 10, 20, 30, ...)
```

The quantum a segment belongs to is simply:
```ruby
quantum_start = (segment_idx / SEGMENTS_PER_QUANTUM) * SEGMENTS_PER_QUANTUM
```

Each quantum FFmpeg is launched with `-ss {start_time} -t 20 -start_number {quantum_start}` and no manifest output flags. It writes its 10 segments and exits cleanly.

### Lifecycle

**First play:**

```
1. Primary FFmpeg starts at segment 0, runs toward end of video
2. Primary writes manifest.m3u8 progressively (updated with each new segment)
3. Primary generates canonical segments with continuous boundaries
4. Primary finishes → complete manifest on disk, durations stored in DB
```

**Seek during first play (uncached position):**

```
1. User seeks to segment 2700
2. Primary is still running (e.g. at segment 500) — left alone
3. Quantum FFmpeg spawned for segment 2700's quantum range
4. Quantum generates segments with estimated -ss, self-terminates
5. Player served from quantum segments immediately
6. Primary eventually reaches segment 2700 — overwrites quantum segments via atomic rename
7. Primary's segments are now canonical for that range
```

**Subsequent plays (primary completed, cache evicted):**

```
1. Full durations stored in DB from primary's completed manifest
2. Quantum FFmpeg spawned for requested range
3. -ss computed from stored durations → exact timestamp, no keyframe mismatch
4. Segments are identical to what the primary originally produced
```

### Two FFmpeg Processes

```ruby
@primary_ffmpeg   # one per scene, runs 0 → end, writes manifest.m3u8
@quantum_ffmpeg   # one per scene, on-demand for seeks, no manifest, self-terminates
```

The primary and quantum can run concurrently for the same scene without dotfile conflicts — they are always writing different segment numbers (primary is behind, quantum is ahead).

**Primary always wins:** when primary's monitor renames a segment (`rename(".2700.ts", "2700.ts")`), it atomically overwrites any existing quantum-generated segment at that position. This is the desired behaviour — primary segments have correct continuous boundaries.

**Quantum is never killed.** It self-terminates via `-t` after generating its segment range. A 10-segment quantum at remux speed (~10x realtime) finishes in ~2 seconds of wall time. If the user seeks again before the quantum finishes, both the old quantum and the new one can run simultaneously — they cover different segment ranges.

**Quantum must not write a manifest.** The FFmpeg command for quantum uses `-hls_segment_filename` to write segment files but omits `-hls_flags` and manifest output, or writes segments directly without HLS muxer (using `-f segment` instead of `-f hls`). The primary's `manifest.m3u8` is the only manifest file on disk.

### Sequence Diagram

**First play with seek:**

```
Browser              Controller              StreamManager              Primary FFmpeg    Quantum FFmpeg
   |                     |                        |                        |
   |-- GET manifest ---->|                        |                        |
   |                     |-- start primary ------>|-- spawn at seg 0 ----->|
   |<-- estimated m3u8 --|                        |                        |-- writes .0.ts, .1.ts...
   |                     |                        |                        |
   |-- GET segment 0 --->|                        |                        |
   |                     |  wait on CV ...        |-- monitor renames ---->|
   |<-- serve 0.ts ------|                        |                        |
   |                     |                        |                        |
   | ... segments 1-15 served from cache ...      |  (primary at seg 20)  |
   |                     |                        |                        |
   | (user seeks to 1:30:00 = segment 2700)       |                        |
   |-- GET segment 2700->|                        |                        |
   |                     |-- request_segment(2700)|                        |
   |                     |                        |  not cached, primary at 20
   |                     |                        |-- spawn quantum -------------------------------->|
   |                     |  wait on CV ...        |                        |                  (est. -ss)
   |                     |                        |                        |          writes .2700.ts...
   |                     |                        |-- monitor renames ---->|                         |
   |<-- serve 2700.ts ---|                        |                        |                         |
   |                     |                        |                        |     (self-terminates)    |
   | ... watching from 2700 ...                   |                        |
   |                     |                        |  (primary still running, reaches 2700 eventually)
   |                     |                        |  primary overwrites quantum segments atomically   |
   |                     |                        |                        |
   |                     |                        |  (primary finishes)    |
   |                     |                        |  full manifest.m3u8 on disk
   |                     |                        |  durations stored in DB
```

**Later play (cache evicted, durations in DB):**

```
Browser              Controller              StreamManager              Quantum FFmpeg
   |                     |                        |                        |
   |-- GET manifest ---->|                        |                        |
   |<-- exact m3u8 ------|  (from stored durations)|                       |
   |                     |                        |                        |
   |-- GET segment 42 -->|                        |                        |
   |                     |-- request_segment(42)->|                        |
   |                     |                        |  not cached, durations known
   |                     |                        |  -ss = sum(durations 0..39) → exact timestamp
   |                     |                        |-- spawn quantum ------>|
   |                     |  wait on CV ...        |                        |-- writes .40.ts...
   |<-- serve 42.ts -----|                        |                        |
   |                     |                        |                        | (self-terminates)
```

### Manifest Serving (Four Tiers)

1. **Complete manifest on disk** (primary finished) — serve directly
2. **Partial manifest on disk** (primary still running) — serve what exists; segments beyond primary's progress trigger quantum
3. **Stored durations in DB** (primary finished previously, manifest file deleted) — reconstruct exact manifest from stored values
4. **No data** (never played) — serve estimated uniform-2s manifest, start primary

### Quantum `-ss` Timestamp Modes

| Mode | When | `-ss` value | Boundary quality |
|---|---|---|---|
| Exact | Stored durations exist for all segments before quantum start | Sum of stored durations | Identical to primary — no discontinuity |
| Estimated | No stored durations (first visit, seek to unknown territory) | `segment_idx * SEGMENT_DURATION` | Approximate — minor keyframe mismatch (remux only) |

For transcode streams (forced keyframes at 2s), both modes produce identical results — the distinction only matters for remux.

### Why Primary Segments Overwrite Quantum

For remux streams, the quantum's estimated `-ss` seeks to the nearest keyframe, which may not align perfectly with where the primary's segments fall. The primary's segments are canonical because they have continuous boundaries from segment 0.

For transcode streams, forced keyframes make all segments identical regardless of start position, so the overwrite is a no-op — same data either way.

### Constants

| Constant | Value | Purpose |
|---|---|---|
| `SEGMENT_DURATION` | 2s | Seconds per `.ts` segment |
| `SEGMENTS_PER_QUANTUM` | 10 | Segments per quantum (20 seconds) |
| `MAX_IDLE_TIME` | 30s | Kill primary after 30s with no segment requests |
| `KEEP_FIRST_SEGMENTS` | 15 | Always preserve segments 0–14 in cache |
| `MAX_CACHE_SIZE` | 5GB | LRU eviction threshold |

### Monitor Loop

```
For each active stream:
  ├─ Rename completed dotfiles (.N.ts → N.ts), broadcast ConditionVariable
  │   └─ Primary overwrites existing quantum segments (atomic rename)
  ├─ Detect primary natural exit → final rename, store all durations from manifest
  ├─ Detect quantum natural exit → final rename (no duration storage, no manifest)
  ├─ Primary idle? (30s no requests) → kill primary
  └─ (no buffer-full checks, no quantum kills)

After stream checks:
  └─ LRU eviction: remove segments beyond first 15 from least-recently-used scenes
     until total tmp/hls/ size is under MAX_CACHE_SIZE
```

### Quantum Size Tradeoffs

| Quantum | Segments | Max seek wait (copy) | Max seek wait (transcode) |
|---|---|---|---|
| 10s / 5 seg | 5 | ~0.8s | ~2-3s |
| 20s / 10 seg | 10 | ~1.8s | ~4-6s |
| 30s / 15 seg | 15 | ~2.8s | ~6-10s |

**20s / 10 segments** is the default — worst-case seek is ~1.8s for copy (barely noticeable), and quantum FFmpeg finishes in ~2s wall time for remux.

### Seek Behaviour

| Scenario | Behaviour |
|---|---|
| Backward seek, segment cached | Instant cache hit |
| Backward seek, uncached | Quantum spawned, primary continues |
| Forward seek, cached | Instant cache hit |
| Forward seek, uncached | Quantum spawned, primary continues |
| Pause | Primary continues running (no kill). Backpressure: nothing requests segments, primary keeps generating to disk |
| Close tab / idle 30s | Primary killed. Quantums already self-terminated |
| Continuous playback | Primary stays ahead; if player catches up, quantum fills gap |

### Edge Cases

- **Last quantum of a video** may be shorter than 20s — FFmpeg hits EOF and exits naturally before `-t` expires. No special handling needed.
- **FFmpeg error mid-quantum** — monitor detects process exit, does final dotfile rename. If the requested segment wasn't produced, `request_segment` times out and returns `:not_found`. A retry from the player will spawn a fresh quantum.
- **Multiple seeks in quick succession** — each seek spawns a quantum for its target range. Multiple quantums can run concurrently since they cover non-overlapping segment ranges. Finished quantums self-terminate; their segments get overwritten by primary later.
- **Cache eviction with partial durations** — if only some segment durations are stored (e.g. primary was killed by idle timeout at segment 500), quantums within the known range use exact timestamps; quantums beyond use estimated timestamps. Next full primary run fills in the remaining durations.

---

## Future Enhancements

- WebM progressive streaming (`/stream.webm`) — for VP9 sources
- MPEG-DASH (`/stream.mpd`) — adaptive streaming
- Resolution variants (4K, 1080p, 720p, 480p, 240p)
- Hardware acceleration — GPU encoder support
