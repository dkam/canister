# Video Streaming Architecture

## Streaming Formats

The app supports 6 video streaming formats via FFmpeg on-the-fly transcoding with hardware acceleration support.

### Progressive Streaming (Single File)

| Endpoint | Description | Codec |
|----------|-------------|-------|
| `/stream` | Direct streaming (no transcoding) | Original |
| `/stream.mp4` | MP4 container | H.264 |
| `/stream.webm` | WebM container | VP9 |
| `/stream.mkv` | MKV container (direct if source is MKV, else transcode) | Original / MKV + Opus audio |

### Adaptive Bitrate Streaming

| Endpoint | Description | Segments |
|----------|-------------|----------|
| `/stream.m3u8` | **HLS** (HTTP Live Streaming) | MPEG-TS (2-second chunks) |
| `/stream.mpd` | **MPEG-DASH** (Dynamic Adaptive Streaming) | WebM video/audio segments (2-second chunks) |

### Features

- On-the-fly FFmpeg transcoding
- Hardware acceleration support (GPU encoders)
- Segmented streaming with 2-second chunks (HLS/DASH)
- Seek support with segment-level precision
- Resolution and bitrate control via `resolution` query parameter

---

## Streaming Mode Selection

| Source file | Mode | Why |
|---|---|---|
| Compatible codec + streamable container (`.mp4`, `.m4v`, `.mov`, `.webm`) | Direct `send_file` | Already browser-ready; range requests handle seeking |
| Compatible codec (H.264, H.265, VP8, VP9) + non-streamable container (`.mkv` etc.) | HLS, stream copy | Can't seek a remux stream; HLS segments solve it |
| Incompatible codec (AV1, etc.) | Pre-transcode to `.mp4` | Must re-encode anyway; do it once offline |

"Compatible codec + wrong container" is the HLS case. Everything else is either serve-direct or pre-transcode.

---

## Why HLS, Not Chunked MP4

The original implementation (`stream_live`) piped a fragmented MP4 from FFmpeg over a chunked HTTP response. Chrome and Firefox accepted it; Safari rejected it with `MEDIA_ERR_SRC_NOT_SUPPORTED`.

**Safari requires** either a `Content-Length` header (complete file) or HLS. Chunked transfer without `Content-Length` is not supported by Safari's native `<video>` element.

HLS works everywhere:
- Safari plays HLS natively
- Chrome/Firefox use VHS (`@videojs/http-streaming`), bundled in the Video.js 8.x CDN build — no extra plugin
- Seeking works because the player can request any segment independently; no FFmpeg restart needed

**Considered alternative**: pre-transcode the remux files to `.mp4` (same as the incompatible codec path) and serve with range requests. This is genuinely simpler — one file, standard HTTP, no segment machinery. HLS is only worth the complexity if you want instant-start playback before a full transcode completes, or finer control over disk usage via LRU eviction. If pre-transcoding everything upfront is acceptable, the simpler path is valid.

---

## Segment Duration

Nominal target: **2 seconds** (`HLS_SEGMENT_DURATION`).

| Segment length | Trade-off |
|---|---|
| Shorter (1–2s) | More precise seeking; more HTTP requests; more files on disk |
| Longer (4–10s) | Fewer requests; coarser seeking; Apple recommends 6s for CDN VOD |

2 seconds matches Stash's implementation. On a local/LAN server HTTP overhead is negligible, so seeking precision wins. The constant is configurable if you want to experiment.

Intra-segment seeking works fine once a segment is buffered — TS segments carry full PTS timestamps on every frame. The segment duration only affects seek precision to *unbuffered* positions.

---

## Stream Copy vs. Transcode, and Keyframes

This is the core complexity of the HLS implementation.

### The keyframe problem

HLS segments must be served as complete, independently-decodable units. Where a segment *starts* matters:

- **Transcode** (`-c:v libx264`): we control the encoder, so we force a keyframe at the start of every segment with `-force_key_frames "expr:gte(t,n_forced*2)"`. Segments are exactly 2 seconds. Playlist `#EXTINF` values are always accurate.
- **Stream copy** (`-c:v copy`): packets are passed through untouched. You cannot insert new keyframes without re-encoding. Segments can only be cut at existing keyframe boundaries.

### The `#EXTINF` accuracy problem

The m3u8 playlist `#EXTINF` value for each segment tells the player how long that segment is. If `#EXTINF` is wrong, the player's time model breaks — seeking lands at the wrong position, or playback stalls.

| Approach | `#EXTINF` accuracy | Segment boundary |
|---|---|---|
| Synthesise playlist from `duration / 2` | Assumes exactly 2s — **wrong** for stream copy if keyframes are sparse | At keyframes (variable length) |
| `-hls_flags split_by_time` + synthesised playlist | Correct — forces time-based cuts | Mid-GOP if no keyframe at boundary |
| Serve FFmpeg's generated `ffmpeg.m3u8` | Always correct — FFmpeg writes actual durations | At keyframes (variable length) |

**`split_by_time`** cuts at the time boundary even without a keyframe. This makes the synthesised playlist accurate but the segment may start mid-GOP. Modern players (VHS, Safari) handle mid-GOP segment starts because TS timestamps are correct; decoding works from the previous keyframe. This is what Stash uses for its copy mode.

**Serving FFmpeg's `ffmpeg.m3u8`** is the most accurate approach for copy mode. The downside: you must wait for FFmpeg to write the file (after its first segment), and if FFmpeg is killed early it writes `#EXT-X-ENDLIST` at the truncation point — the playlist then describes a shorter video than the source. This caused a real bug (playlist showed 47s for a multi-minute video).

**Current approach**: `split_by_time` + synthesised playlist. Segments are reliably ~2s; `#EXTINF:2.0` is accurate enough for the player. Same approach as Stash.

### AV1

AV1 cannot be muxed into MPEG-TS with meaningful player support. AV1 sources are always transcoded to H.264, regardless of container. `-force_key_frames` applies.

---

## On-Demand Generation

FFmpeg is spawned as a detached OS process (`spawn` + `Process.detach`). The Puma thread polls for segment files.

**Only one FFmpeg per scene at a time.** The `.ffmpeg_pid` file tracks the running process. `running?` checks `Process.kill(0, pid)` before spawning a new one — prevents concurrent segment requests from killing each other's FFmpeg.

**Buffer window**: FFmpeg generates a fixed window of segments (15 = 30 seconds), then is killed. When the player requests a segment outside the buffer, FFmpeg restarts from the nearest existing segment.

**Seeking**: if the player requests segment N and FFmpeg is running but behind, the `running?` guard means we wait. If FFmpeg is not running (buffer exhausted), we restart from the nearest prior segment. This matches Stash's gap-based restart logic (`maxSegmentGap = 5` segments in their implementation).

**Puma thread blocking**: `stream_hls_segment` sleeps 0.1s in a loop waiting for the segment file, for up to 15 seconds. This blocks a Puma thread. Once segments are cached, requests return immediately. Increasing Puma's thread count (`RAILS_MAX_THREADS`) is the lever if this becomes a bottleneck.

---

## Playlist Generation

The m3u8 is generated in Ruby from `scene.duration`:

```
total_segments = (duration / 2.0).ceil
each segment: #EXTINF:2.0  (last segment gets the remainder)
```

This is served immediately — no waiting for FFmpeg. The segment URLs point at `stream_hls_segment`, which generates on demand.

`hls_playlist` lives on the `Scene` model. The URL lambda is passed in from the controller (models don't know about routes).

---

## What Stash Does

Stash (the reference Go implementation) uses the same core approach:
- Synthesised m3u8 from duration
- `-force_key_frames` for transcode, `-hls_flags split_by_time` for copy
- `maxSegmentBuffer = 15` segments ahead, then pause transcode
- `maxSegmentGap = 5` — if seek is >5 segments from current position, restart transcode
- `maxIdleTime = 30s` — stop transcode if no requests for 30 seconds

Our implementation follows the same pattern without the goroutine-based monitor loop (we use Solid Queue jobs and Puma polling instead).

---

## Cache Eviction

`CleanHlsJob` enforces `HLS_CACHE_GB` (default 5 GB) via LRU:

- `.last_accessed` file in each HLS dir is `touch`ed on every playlist/segment request
- Dirs are sorted by `.last_accessed` mtime, oldest deleted first until under the limit
- Running FFmpeg is killed before its dir is deleted

---

## Directory Layout

```
transcodes/
  {checksum}.mp4          # pre-generated transcode (incompatible codec path)
  hls/
    {checksum}/
      0.ts, 1.ts, ...     # MPEG-TS segments (~2s each)
      .last_accessed       # touched on each request (LRU)
      .ffmpeg_pid          # PID of running FFmpeg (if any)
      ffmpeg.m3u8          # FFmpeg's internal playlist — not served
      ffmpeg.log           # FFmpeg stderr — useful for debugging
```

---

## Configuration

| Variable | Default | Description |
|---|---|---|
| `TRANSCODE_PATH` | `{root}/transcodes` | Pre-generated transcode files |
| `HLS_PATH` | `{root}/transcodes/hls` | HLS segment cache |
| `HLS_SEGMENT_DURATION` | `2` | Target segment length in seconds |
| `HLS_CACHE_GB` | `5` | LRU eviction threshold |
