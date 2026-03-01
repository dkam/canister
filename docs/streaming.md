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
| `app/controllers/scenes/streams_controller.rb` | Direct streaming + progressive MP4 streaming |
| `app/controllers/scenes_controller.rb` | Stream endpoint URL building |
| `config/routes.rb` | `/stream` and `/stream_mp4` route definitions |

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

## Future Enhancements

- WebM progressive streaming (`/stream.webm`) — for VP9 sources
- MKV progressive streaming (`/stream.mkv`) — for MKV sources
- HLS (`/stream.m3u8`) — adaptive streaming with segment caching
- MPEG-DASH (`/stream.mpd`) — adaptive streaming with segment caching
- Resolution variants (4K, 1080p, 720p, 480p, 240p)
- Stream process manager — prevent duplicate FFmpeg instances
- Hardware acceleration — GPU encoder support
