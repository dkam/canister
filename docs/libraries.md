# Library Model + WebDAV Backend Plan

## Context

The Library model already exists (`app/models/library.rb`) with a `kind` enum including `webdav`. Scenes have `belongs_to :library, optional: true`. The goal is to introduce a backend abstraction so that streaming, scanning, and file access work transparently across local and remote (WebDAV) sources.

The critical challenge: the entire pipeline (streaming, HLS, transcoding, scanning) currently assumes local filesystem paths (`@scene.path`, `File.exist?`, `FFMPEG::Movie.new(path)`). We need to make this work for remote files without rewriting the streaming infrastructure.

## Key Insight: FFmpeg Reads HTTP Natively

FFmpeg's built-in HTTP protocol handler supports range requests out of the box. This means:
- `ffmpeg -i "http://webdav.example.com/videos/movie.mp4" ...` just works
- HLS segmentation, progressive MP4 piping, and metadata probing all work with HTTP URLs
- No need to download entire files before transcoding

For WebDAV specifically, read operations are just HTTP GET with Range headers — FFmpeg handles this transparently.

## Architecture: Library Backend Strategy

### 1. Backend Classes (`app/models/library/`)

```
Library::Backend          # base class / interface
Library::LocalBackend     # filesystem operations
Library::WebdavBackend    # HTTP/WebDAV with auth
```

Each backend implements:
- `#list_files(extensions:)` → array of relative paths (for scanning)
- `#file_exists?(relative_path)` → boolean
- `#ffmpeg_input(relative_path)` → string (local path or HTTP URL for FFmpeg `-i`)
- `#file_size(relative_path)` → integer
- `#read_range(relative_path, range)` → IO/string (for direct byte-range serving)

### 2. Library Model Changes

```ruby
# app/models/library.rb
class Library < ApplicationRecord
  def backend
    @backend ||= case kind
    when "local"  then Library::LocalBackend.new(self)
    when "webdav" then Library::WebdavBackend.new(self)
    end
  end
end
```

Add columns to Library:
- `username` (string, encrypted) — WebDAV auth
- `password` (string, encrypted) — WebDAV auth

### 3. Scene Path Semantics — Always Relative

All scene paths become **relative to their library's path**. For example:
- Library path: `/Videos/` → Scene path: `movies/movie.mp4` → absolute: `/Videos/movies/movie.mp4`
- Library path: `https://dav.example.com/media/` → Scene path: `movies/movie.mp4` → FFmpeg input: `https://user:pass@dav.example.com/media/movies/movie.mp4`

Existing scenes will be deleted (only 5-6 test videos) and re-scanned.

New Scene methods:
```ruby
def ffmpeg_input
  library.backend.ffmpeg_input(path)
end

def absolute_path  # local files only
  library.backend.absolute_path(path)
end
```

### 4. StreamManager Changes

The StreamManager currently uses `stream.scene_path` (absolute local path) to build FFmpeg commands. Change this to use the `ffmpeg_input` which returns either a local path or an HTTP URL.

Key change in `build_hls_ffmpeg_command`:
```ruby
cmd += ["-i", stream.scene_path]  # scene_path now comes from scene.ffmpeg_input
```

For WebDAV URLs, add FFmpeg HTTP options:
```ruby
if stream.scene_url  # remote source
  cmd += ["-headers", "Authorization: Basic #{credentials}\r\n"]
end
```

### 5. Streaming Strategy by Type

| Stream Type | Local Library | WebDAV Library |
|------------|--------------|----------------|
| **Direct** (byte-range) | `send_file` local path | Proxy range requests through app OR skip (prefer HLS) |
| **HLS** | FFmpeg reads local file | FFmpeg reads HTTP URL (range requests automatic) |
| **Progressive MP4** | FFmpeg reads local file | FFmpeg reads HTTP URL |
| **Scanning** | `Dir.glob` | WebDAV PROPFIND |
| **Metadata** | `FFMPEG::Movie.new(path)` | `FFMPEG::Movie.new(url)` (ffprobe supports HTTP) |
| **Screenshots** | FFmpeg from local path | FFmpeg from HTTP URL |

### 6. WebDAV Backend Implementation

**Gem**: Use `net/http` directly (WebDAV PROPFIND is just HTTP). No extra gem needed.

```ruby
# app/models/library/webdav_backend.rb
class Library::WebdavBackend < Library::Backend
  def list_files(extensions:)
    # PROPFIND with Depth: infinity (or recursive Depth: 1)
    # Parse multistatus XML response
    # Filter by extensions
  end

  def ffmpeg_input(relative_path)
    # Returns full URL with credentials embedded
    uri = URI.join(library.path, relative_path)
    uri.user = library.username
    uri.password = library.password
    uri.to_s
  end

  def file_exists?(relative_path)
    # HTTP HEAD request
  end

  def read_range(relative_path, range)
    # HTTP GET with Range header — for checksum calculation
  end
end
```
```

### 7. Caching Strategy — HLS Segments ARE the Cache

FFmpeg reads from WebDAV via HTTP range requests and writes HLS `.ts` segments to `tmp/hls/{scene_id}/` — the exact same local cache used for local files. No separate source file caching needed.

- FFmpeg pulls only the bytes it needs from the remote file (range requests)
- Segments land in the same local `tmp/hls/` directory
- All existing cache management works unchanged: LRU eviction, buffer limits, segment reuse
- Pre-generated transcodes and screenshots are also generated from the HTTP URL and cached locally via ActiveStorage

### 8. Direct Streaming for WebDAV

Skip direct byte-range streaming for remote libraries. Remote scenes only offer HLS and progressive MP4 streams. HLS already provides good seeking via segments.

### 9. Authentication

Use URL-embedded credentials (`http://user:pass@host/path`) for FFmpeg/ffprobe — simplest approach that works everywhere. Filter credentials from Rails logs.

## Implementation Steps

### Phase 1: Backend Abstraction + Relative Paths
1. Create `Library::Backend` base class with interface
2. Create `Library::LocalBackend` wrapping current filesystem logic
3. Add `Library#backend` method
4. Update `Scene` — add `#ffmpeg_input`, `#absolute_path` delegating to backend
5. Scene paths now stored relative to library path (delete existing scenes, re-scan)
6. Update `StreamManager` to use `scene.ffmpeg_input` instead of raw `scene.path`
7. Update `Streamable` concern — `stream_file_exists?` uses backend, skip direct for remote
8. Update `StreamsController` — use `ffmpeg_input` for FFmpeg commands, `absolute_path` for `send_file`

### Phase 2: WebDAV Backend
1. Create `Library::WebdavBackend`
2. Implement PROPFIND-based file listing (recursive, filter by extension)
3. Implement `ffmpeg_input` returning authenticated HTTP URLs (credentials in URL)
4. Implement `read_range` for partial file downloads (checksum calculation)
5. Add `username`/`password` encrypted columns to Library migration
6. Filter credentials from Rails logs

### Phase 3: WebDAV Scanning & Metadata
1. Update `Canister::Tasks::Scan` to work with remote files via backend
2. Checksum calculation: HTTP Range requests for first/last 64KB (OpenSubtitles hash)
3. Metadata extraction via `FFMPEG::Movie.new(authenticated_url)` (ffprobe supports HTTP)
4. Screenshot generation from HTTP URL

### Phase 4: Library CRUD UI
1. `LibrariesController` with standard CRUD
2. Form with kind selector, path, credentials (show/hide based on kind)
3. Connection test endpoint (PROPFIND root to verify WebDAV access)

## Files to Create/Modify

**Create:**
- `app/models/library/backend.rb` — base class
- `app/models/library/local_backend.rb` — filesystem operations
- `app/models/library/webdav_backend.rb` — HTTP/WebDAV operations
- `app/controllers/libraries_controller.rb`
- `app/views/libraries/` (index, new, edit, _form)
- `db/migrate/xxx_add_credentials_to_libraries.rb`

**Modify:**
- `app/models/library.rb` — add `#backend`, encrypted credentials
- `app/models/scene.rb` — add `#ffmpeg_input`, `#absolute_path`, remove hardcoded path assumptions
- `app/models/concerns/streamable.rb` — backend-aware availability checks (skip direct for remote)
- `app/lib/canister/stream_manager.rb` — use `scene.ffmpeg_input` instead of raw path
- `app/controllers/scenes/streams_controller.rb` — skip direct stream for remote, use `ffmpeg_input`
- `app/lib/canister/tasks/scan.rb` — use backend for file listing, relative paths, range-request checksums
- `config/routes.rb` — add library routes

## Verification

1. **Local libraries**: All existing functionality continues to work unchanged
2. **WebDAV scanning**: Point at a WebDAV server, run scan, verify scenes are created with correct metadata
3. **WebDAV HLS**: Play a remote video via HLS, verify segments are generated and served
4. **WebDAV progressive**: Play via progressive MP4, verify FFmpeg reads from HTTP
5. **Seeking**: Verify HLS seeking works (StreamManager restarts FFmpeg with `-ss` on remote URL)
