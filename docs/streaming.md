# Video Streaming Architecture

## Streaming Formats

The app supports 6 video streaming formats via FFmpeg on-the-fly transcoding with hardware acceleration support.

### Progressive Streaming (Single File)

| Endpoint | Description | Codec |
|----------|-------------|-------|
| `/stream` | Direct streaming (no transcoding) | Original |
| `/stream.mp4` | MP4 container | H.264 |
| `/stream.webm` | WebM container | VP9 |
| `/stream.mkv` | MKV container (copy only — offered when source is already MKV) | Original + Opus audio |

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

## How a Format Is Chosen

### Backend: Building the stream list

The backend generates an ordered list of available stream endpoints for each video based on the file's codec metadata. It does not pick one format — it offers everything that's valid and lets the frontend decide.

**Audio codec compatibility** gates which endpoints are offered:

| Container | Allowed audio codecs |
|-----------|----------------------|
| MP4 | AAC, MP3, Opus |
| WebM | Vorbis, Opus |
| MKV | AAC, MP3, Vorbis, Opus |

The direct stream (`/stream`) is only included if the audio codec is compatible with the source container, or if a pre-transcoded copy already exists.

MKV is only offered if the source file is already an MKV — there's no point transcoding to MKV otherwise since it just does a container copy.

Resolution variants are filtered by a `max_streaming_transcode_size` config (Original, 4K, 1080p, 720p, 480p, 240p). Each applicable format gets one entry per resolution tier smaller than the source.

The resulting list — each entry with a URL, MIME type, and label — is returned to the client (via GraphQL as `sceneStreams`).

### Frontend: Trying sources in order

The player receives the full list and works through it:

1. **Safari filter** — MP4/WebM/MKV transcodes are removed for Safari. Safari only gets the direct stream and HLS/DASH.
2. **Play the first source** — usually the direct stream.
3. **Auto-fallback** — if playback fails with `MEDIA_ERR_SRC_NOT_SUPPORTED` or `MEDIA_ERR_DECODE`, the player silently moves to the next source. If the user manually selected a format, fallback is disabled.
4. **User override** — a source selector dropdown lets the user force a specific format.

### Seeking

Progressive transcodes (`/stream.mp4`, `/stream.webm`, `/stream.mkv`) require a `?start=<seconds>` parameter to seek — the FFmpeg process restarts at that offset.

HLS and DASH handle seeking internally via segment index. The player treats these as "direct" for seek purposes even though transcoding may be happening underneath.

---

## Summary

```
Video codecs in DB
    ↓
Backend validates audio codec against each container format
    ↓
Generates ordered list: [direct, mp4, webm, mkv, m3u8, mpd] × resolutions
    ↓
GraphQL: sceneStreams
    ↓
Frontend filters for Safari (removes mp4/webm/mkv transcodes)
    ↓
Video.js tries first source (direct stream)
    ↓
Codec error? → auto-try next source in list
    ↓
User can manually override at any time
```

---

## Progressive Transcode Lifecycle

Progressive transcode (`/stream.mp4`, `/stream.webm`, `/stream.mkv`) shares identical behavior across formats. Only the FFmpeg output format differs.

### Request Flow

**1. Initial load:**
```
Browser → GET /scenes/5/stream.mp4?start=0
FFmpeg starts → -ss 0 -i input.mkv -c:v copy -ac 2 -f mp4 pipe:1
              → transcoding from 0 to end
```

**Stash implementation:**
- `tmp/stash/internal/api/routes_scene.go:102-133` — `StreamMp4`, `StreamWebM`, `StreamMKV` endpoints
- `tmp/stash/internal/api/routes_scene.go:145-166` — `streamTranscode` parses `?start=` parameter and creates `TranscodeOptions`
- `tmp/stash/pkg/ffmpeg/stream_transcode.go:223-246` — `ServeTranscode` spawns FFmpeg and pipes to response

**2. Seek to unbuffered position:**
```
Browser closes connection → io.Copy returns EPIPE/ECONNRESET
FFmpeg killed via context cancellation
Browser → GET /scenes/5/stream.mp4?start=45.5 (NEW FFmpeg process)
```

**Stash implementation:**
- `tmp/stash/pkg/ffmpeg/stream_transcode.go:299-302` — `io.Copy(w, stdout)` detects broken pipe (`EPIPE`/`ECONNRESET`)
- `tmp/stash/pkg/ffmpeg/stream.go:83-133` — `StreamRequestContext` wraps `r.Context()` for automatic cancellation
- `tmp/stash/pkg/ffmpeg/stream_transcode.go:267` — `ctx.AttachCommand(cmd)` ties FFmpeg lifecycle to request context

**3. Browser pauses:**
```
FFmpeg: io.Copy(w, stdout)
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

**Stash implementation:**
- `tmp/stash/pkg/ffmpeg/stream_transcode.go:248-289` — `getTranscodeStream` spawns FFmpeg with stdout pipe
- `tmp/stash/pkg/ffmpeg/stream_transcode.go:299` — `io.Copy(w, stdout)` handles backpressure via goroutine blocking

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

**Stash implementation:**
- `tmp/stash/pkg/ffmpeg/stream_transcode.go:293-295` — Sets `Cache-Control: no-store` and MIME type, no `Content-Length`

### FFmpeg Process Lifecycle

| Scenario | FFmpeg Behavior |
|----------|----------------|
| Browser seeks to new position | Old FFmpeg killed, new one spawned |
| Browser pauses | FFmpeg blocks on full pipe (backpressure) |
| Browser resumes | FFmpeg unblocks, continues transcoding |
| Browser stops/closes tab | FFmpeg killed via context cancellation |
| Error during transcode | Process exits, error logged |

This is why HLS is preferred for frequent seeking — segments are cached and reusable, avoiding FFmpeg restart overhead.

**Stash implementation:**
- `tmp/stash/pkg/ffmpeg/stream_transcode.go:270-289` — Goroutine monitors FFmpeg exit, logs errors (ignores `ExitError` since process is killed)
- `tmp/stash/pkg/ffmpeg/stream_transcode.go:284-288` — Only logs non-exit errors (process is always forcibly killed)
- `tmp/stash/pkg/ffmpeg/stream.go:88-93` — `NewStreamRequestContext` wraps HTTP request context for cancellation

### Format Differences

All three progressive formats use identical request/response lifecycle:

| Format | Video Codec | Audio Codec | Seek Support |
|---------|-------------|-------------|--------------|
| `.stream.mp4` | Copy or transcode to H.264 | Copy or transcode to AAC | `?start=` |
| `.stream.webm` | Copy or transcode to VP9 | Copy or transcode to Opus | `?start=` |
| `.stream.mkv` | Copy only | Copy only | `?start=` |

MKV is special — it never re-encodes, just remuxes (`.stream.mkv` = direct container stream).

**Stash implementation:**
- `tmp/stash/pkg/ffmpeg/stream_transcode.go:95-142` — `StreamTypeMP4`, `StreamTypeWEBM`, `StreamTypeMKV` define codec/format args
- `tmp/stash/pkg/ffmpeg/stream_transcode.go:152-185` — `FileGetCodec` decides copy vs transcode based on codec compatibility
- `tmp/stash/pkg/ffmpeg/stream_transcode.go:187-221` — `makeStreamArgs` builds FFmpeg command with `-ss` for seeking

**1. Initial load:**
```
Browser → GET /scenes/5/stream.mp4?start=0
FFmpeg starts → -ss 0 -i input.mkv -c:v copy -ac 2 -f mp4 pipe:1
              → transcoding from 0 to end
```

**2. Seek to unbuffered position:**
```
Browser closes connection → io.Copy returns EPIPE/ECONNRESET
FFmpeg killed via context cancellation
Browser → GET /scenes/5/stream.mp4?start=45.5 (NEW FFmpeg process)
```

**3. Browser pauses:**
```
FFmpeg: io.Copy(w, stdout)
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

### FFmpeg Process Lifecycle

| Scenario | FFmpeg Behavior |
|----------|----------------|
| Browser seeks to new position | Old FFmpeg killed, new one spawned |
| Browser pauses | FFmpeg blocks on full pipe (backpressure) |
| Browser resumes | FFmpeg unblocks, continues transcoding |
| Browser stops/closes tab | FFmpeg killed via context cancellation |
| Error during transcode | Process exits, error logged |

This is why HLS is preferred for frequent seeking — segments are cached and reusable, avoiding FFmpeg restart overhead.

### Format Differences

All three progressive formats use identical request/response lifecycle:

| Format | Video Codec | Audio Codec | Seek Support |
|---------|-------------|-------------|--------------|
| `.stream.mp4` | Copy or transcode to H.264 | Copy or transcode to AAC | `?start=` |
| `.stream.webm` | Copy or transcode to VP9 | Copy or transcode to Opus | `?start=` |
| `.stream.mkv` | Copy only | Copy only | `?start=` |

MKV is special — it never re-encodes, just remuxes (`.stream.mkv` = direct container stream).
