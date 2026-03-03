# Video Streaming Architecture

## Streaming Formats

The app supports 2 video streaming formats via FFmpeg on-the-fly transcoding.

### Progressive Streaming (Single File)

| Endpoint | Description | Codec | Scope |
|----------|-------------|-------|--------|
| `/stream` | Direct streaming (byte-range) | Original | Implemented |
| `/stream.mp4` | MP4 container (smart codec selection) | H.264 (copy) or transcoded | Implemented |

### Adaptive Bitrate Streaming

| Endpoint | Description | Segments | Scope |
|----------|-------------|----------|--------|
| `/stream.m3u8` | **HLS** (HTTP Live Streaming) | MPEG-TS (2-second chunks) | Implemented |

---

## How a Format Is Chosen

### Backend: Building Stream List

The backend generates an ordered list of available stream endpoints for each video based on the file's codec metadata. It does not pick one format — it offers everything that's valid and lets the frontend decide.

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
3. **User override** — a source selector dropdown lets user force a specific format

### Seeking

Direct streaming (`/stream`) uses byte-range requests for seeking.

Progressive streaming (`/stream.mp4`) requires a `?start=<seconds>` parameter — the FFmpeg process restarts at that offset.

---

## Progressive Transcode Lifecycle

Progressive transcode (`/stream.mp4`) uses per-request FFmpeg processes with automatic cleanup.

### Request Flow

**1. Initial load:**
```
Browser → GET /scenes/5/stream.mp4?start=0
FFmpeg starts → -ss 0 -i input.mkv -c:v copy -ac 2 -f mp4 pipe:1
```

**2. Seek to unbuffered position:**
```
Browser closes connection → Open3.popen3 returns EPIPE/ECONNRESET
FFmpeg killed automatically (process dies when pipe closes)
Browser → GET /scenes/5/stream.mp4?start=45.5 (NEW FFmpeg process)
```

**3. Browser pauses:**
FFmpeg blocks on full pipe (backpressure). No wasted network traffic.

**4. Browser resumes:**
Browser reads → TCP buffer drains → pipe buffer drains → FFmpeg unblocks.

### FFmpeg Process Lifecycle

| Scenario | FFmpeg Behavior |
|----------|----------------|
| Browser seeks to new position | Old FFmpeg killed, new one spawned |
| Browser pauses | FFmpeg blocks on full pipe (backpressure) |
| Browser resumes | FFmpeg unblocks, continues transcoding |
| Browser stops/closes tab | FFmpeg killed (SIGPIPE from closed pipe) |
| Error during transcode | Process exits, error logged |

---

## HLS Streaming Architecture

Single-process model: **one FFmpeg process per scene**, killed and restarted on seek. This matches the Stash approach and eliminates audio glitches at segment boundaries.

### Why Single-Process (and What Failed Before)

The previous architecture used two types of FFmpeg processes:

- **Primary** — long-running process from segment 0 to completion
- **Quantum** — short-lived process spawned on demand for seek/prefetch, self-terminating via `-t`

The problem: each quantum was an independent FFmpeg encode. When the player transitioned between segments from different encodes, there was an **audible pop/glitch** at the boundary. Two independent encodes of the same source at the same timestamp produce slightly different bitstreams — different encoder state, different audio codec warmup, slightly different timing (~50ms start-time difference, ~140ms duration difference confirmed via ffprobe).

Approaches tried and failed:

| Approach | Outcome |
|----------|---------|
| `-output_ts_offset` to align quantum timestamps | Broke `-f segment` muxer — produced 1 segment instead of 10 |
| `-copyts` to preserve source timestamps | Broke `-f segment` muxer entirely |
| `-reset_timestamps 1` per segment | Fixed numbering but not encoder state discontinuity |
| `#EXT-X-DISCONTINUITY` tags in manifest | Player resets decoder but glitch is still audible |
| Starting quantum 1 segment early (preroll absorption) | Fixed audio preroll, but not encoder state discontinuity |
| No `-copyts` on quantum (PTS from 0) + discontinuity | "Almost right" but 83ms PTS mismatch confused players |

**Root cause:** You cannot mix output from independent encodes without audible artifacts on transcoded streams. The only fix is to never mix — use a single continuous encode.

### Current Architecture

One FFmpeg process per scene. Kill and restart on seek. Never mix output from two encodes.

```
Player requests segment 42
  ├─ On disk → serve immediately
  └─ Not on disk:
       ├─ No FFmpeg running → start from segment 42
       ├─ FFmpeg running, will reach 42 soon → wait
       └─ FFmpeg running, too far away → kill, restart from 42
```

All segments served to the player come from a single encode run. When the player seeks, the old process is killed and a new one starts from the seek point. There are no discontinuity tags because there are no discontinuities.

### Constants (`Hls::StreamManager`)

| Constant | Value | Purpose |
|---|---|---|
| `SEGMENT_DURATION` | 2s | Seconds per `.ts` segment |
| `SEGMENT_WAIT_TIMEOUT` | 15s | Max seconds to wait for segment before returning 404 |
| `MAX_SEGMENT_GAP` | 5 | Kill and restart if request is >5 segments ahead of current position |
| `MAX_SEGMENT_BUFFER` | 15 | Stop FFmpeg when 15 segments buffered ahead of playback |
| `MAX_IDLE_TIME` | 30s | Stop FFmpeg after 30 seconds of no segment requests |
| `MONITOR_INTERVAL` | 200ms | Background check frequency |
| `KEEP_FIRST_SEGMENTS` | 15 | Preserve segments 0–14 during cache eviction |
| `MAX_CACHE_SIZE` | 5GB | LRU eviction threshold (`HLS_MAX_CACHE_SIZE_GB` env var) |

### Request Flow

**1. Manifest request (`stream_hls`):**

Always serves an estimated manifest with uniform 2-second segments. No tiers, no disk manifest lookup. The manifest is a prediction of segment count based on video duration — the player uses it to build its timeline.

**2. Segment request (`stream_hls_segment`):**

```
Browser → GET /scenes/{id}/stream_hls/42
  ├─ Segment on disk → touch (update last_requested_segment), serve immediately
  └─ Not on disk:
       ├─ No process running → start FFmpeg from segment 42
       ├─ Process running, gap ≤ 5 → wait (process will reach it)
       ├─ Process running, gap > 5 → kill, restart from 42
       └─ Segment behind current position → kill, restart from 42
           └─ Wait on ConditionVariable (up to 15s) → serve or 404
```

**3. Monitor thread (runs every 200ms):**

```
For each scene with an active transcode:
  ├─ Rename completed dotfiles (.N.ts → N.ts), broadcast CV
  ├─ Detect FFmpeg exit → final rename, save durations, clean manifest
  ├─ Buffer limit check → if 15 segments ahead of playback, stop FFmpeg
  └─ Idle check → if no requests for 30s, stop FFmpeg

After stream checks:
  └─ LRU cache eviction (skipping scenes with active transcodes)
```

### Buffer Limit

The buffer limit prevents FFmpeg from encoding the entire file when the player is watching sequentially. Once `MAX_SEGMENT_BUFFER` (15) segments exist on disk ahead of the last requested segment, FFmpeg is stopped. When the player catches up and requests a segment that doesn't exist, FFmpeg restarts from that point.

This is checked against `last_requested_segment` (what the player is watching), not `highest_generated` (what FFmpeg has produced). The distinction matters — without it, FFmpeg never stops because the check looks ahead of its own output rather than ahead of playback.

### Segment Reuse

Segments from previous encode runs persist on disk and are reused without re-encoding:

- Player requests segment 5, it's already on disk from a previous session → served immediately, no FFmpeg started
- FFmpeg stops at segment 30 (buffer full), player catches up to segment 28 → segments 28-30 served from disk, FFmpeg restarts from 31
- Player seeks backward to segment 10 → FFmpeg is killed, but segment 10 is still on disk → served immediately

Segments are only cleaned up by LRU cache eviction when the total cache exceeds `MAX_CACHE_SIZE`.

### Dotfile Pattern

FFmpeg writes segments as dotfiles (`.N.ts`). The monitor renames `.N.ts → N.ts` once the *next* dotfile appears, guaranteeing the segment is complete before serving.

```
FFmpeg writing:  .0.ts  .1.ts  .2.ts  .3.ts ...
After rename:     0.ts   1.ts   2.ts          ← .3.ts still being written
```

When FFmpeg exits, the last dotfile is renamed immediately (no next file to confirm, but exit means it's complete).

### Stored Segment Durations

Durations are saved to `Scene#hls_segment_durations` as a hash (`{"0" => 1.999, "1" => 2.001, ...}`) incrementally during each monitor tick. This data is kept for potential future use (resume, analytics) but is **not** used for manifest generation — the manifest is always estimated.

### Seek Behaviour

| Scenario | Behaviour |
|---|---|
| Forward seek, segment cached | Instant serve from disk |
| Forward seek, uncached, close to FFmpeg | Wait for FFmpeg to reach it |
| Forward seek, uncached, far from FFmpeg | Kill FFmpeg, restart from seek point |
| Backward seek, segment cached | Instant serve from disk |
| Backward seek, uncached | Kill FFmpeg, restart from seek point |
| Sequential playback | Segments served from disk; FFmpeg pauses when 15 ahead |
| Pause | FFmpeg continues until buffer limit, then stops |
| Close tab / idle 30s | FFmpeg stopped |

### Cache Eviction

Segments are stored in `tmp/hls/{scene_id}/`. When total size exceeds `MAX_CACHE_SIZE`, the monitor evicts least-recently-accessed scenes, preserving segments 0–14 for fast restart. Scenes with active transcodes are never evicted.

### Multiple Puma Workers

Each worker has its own `StreamManager` singleton. Coordination happens through the filesystem — if another worker's FFmpeg already generated a segment, the `.ts` file exists and is served immediately.

---

## FFmpeg Pitfalls (Lessons Learned)

### `-f segment` vs `-f hls`

The segment muxer (`-f segment`) only splits on **keyframes** by default. Use `-break_non_keyframes 1` to allow time-based splits. The HLS muxer (`-f hls -hls_flags split_by_time`) does this automatically.

`-copyts` works fine with `-f hls` but **breaks `-f segment`** — output timestamps preserve the input seek position, which misaligns with split-point calculations. Similarly, `-output_ts_offset` breaks `-f segment`.

### 0-byte dotfile race condition

```
1. FFmpeg creates .12.ts (0 bytes — just opened for writing)
2. Monitor sees 0-byte .12.ts, deletes it
3. FFmpeg writes to the deleted inode (file descriptor still valid)
4. FFmpeg closes file — data written to deleted inode, lost forever
```

**Fix:** Only delete 0-byte dotfiles after FFmpeg has exited.

### Monitor must track processes with PID, not just alive processes

A process that exits between monitor ticks must still be detected. Filter by "has PID" (includes just-exited), not "process alive" (misses exits).

### Independent encodes cannot be mixed

This is the key lesson. Two FFmpeg processes encoding the same source at the same timestamp produce different bitstreams. Mixing segments from different encodes causes audible artifacts. The only solution is one process per stream — kill and restart on seek, never splice.

---

## Implementation Files

| File | Purpose |
|------|---------|
| `app/models/concerns/streamable.rb` | Stream configuration generation with codec flags |
| `app/controllers/scenes/streams_controller.rb` | Direct streaming, progressive MP4, HLS manifest + segment serving |
| `app/services/hls/stream_manager.rb` | Singleton orchestrator — one transcode process per scene |
| `app/services/hls/transcode_process.rb` | Single FFmpeg process lifecycle — start, stop, monitor, dotfile rename |
| `app/services/hls/ffmpeg_command.rb` | FFmpeg command builder (single unified method) |
| `app/services/hls/manifest_builder.rb` | Estimated uniform-duration manifest generation |
| `app/services/hls/segment_cache.rb` | LRU cache, eviction, disk operations |

---

## Configuration

| Variable | Default | Description |
|---|---|---|
| `HLS_MAX_CACHE_SIZE_GB` | `5` | Max HLS segment cache size before LRU eviction |

---

## Future Enhancements

- Resolution variants (1080p, 720p, 480p)
- Hardware acceleration — GPU encoder support
