# Scanning Pipeline

The scan pipeline imports media files from libraries into the database. It's designed to be fast — the synchronous scan only does lightweight I/O, with all heavy processing deferred to background jobs.

## Overview

```
ScanService.run
  └─ for each file in library:
       1. Path lookup     — skip if already in DB
       2. Checksum         — OpenSubtitles hash (~275ms remote, fast local)
       3. Checksum lookup  — detect renames (same hash, different path)
       4. DB insert        — Video record with path + checksum only
       5. Enqueue jobs ──┬─ ProbeVideoJob
                         ├─ GenerateScreenshotJob
                         └─ GeneratePreviewJob
```

## Synchronous Phase (ScanService)

The scan loop does the minimum work needed to create a database record:

- **Path check** — `Video.find_by(path:)`. If the file is already known, skip it (enqueue screenshot if missing).
- **Checksum** — Computes an [OpenSubtitles hash](https://trac.opensubtitles.org/projects/opensubtitles/wiki/HashSourceCodes) using the first and last 64KB of the file. For remote libraries this requires two HTTP range requests (~275ms). Local files are near-instant.
- **Rename detection** — If a checksum matches an existing record with a different path, update the path instead of creating a duplicate.
- **Insert** — Creates a Video record with just `path`, `library_id`, and the checksum. No metadata (duration, codecs, resolution) at this point.

## Background Jobs (SolidQueue, `:media` queue)

All heavy work runs asynchronously. Jobs are idempotent and can run in any order.

### ProbeVideoJob

Runs `ffprobe` against the video file to extract metadata:
- duration, bitrate, video/audio codecs, width, height, framerate

**Idempotent:** Skips if `video.duration` is already populated (`video.probed?`).

The ffprobe logic is exposed as `ProbeVideoJob.ffprobe(path)` for reuse, and `Video#probe!` wraps the full probe-and-update cycle.

### GenerateScreenshotJob

Extracts a JPEG screenshot from the video using ffmpeg.

- Default timecode: 20% of video duration
- Optional: pass a specific timecode in seconds as the second argument
- **Dependency:** Calls `video.probe!` inline if the video hasn't been probed yet, so it works regardless of whether ProbeVideoJob has run.

Usage:
```ruby
GenerateScreenshotJob.perform_later(video.id)           # screenshot at 20%
GenerateScreenshotJob.perform_later(video.id, 45.0)     # screenshot at 45s
```

### GeneratePreviewJob

Generates an animated preview clip for the video. Runs via `GeneratePreviewService`.

## Instrumentation

The scan service uses `ActiveSupport::Notifications` for timing:

- `list_files.scan_service` — time to list files from the library backend
- `checksum.scan_service` — time to compute the OpenSubtitles hash

These appear in the Rails log as:
```
  List files (1234.5ms) library_name
  Checksum (275.6ms) filename.mp4
```

## Running a Scan

```ruby
# From console
ScanService.run                           # scan all libraries
ScanService.run(library_id: library.id)   # scan a specific library

# Via rake task
rails metadata:scan

# Via the Library model
library.scan  # enqueues ScanJob
```

## Key Files

- `app/services/scan_service.rb` — scan loop
- `app/jobs/probe_video_job.rb` — ffprobe metadata extraction
- `app/jobs/generate_screenshot_job.rb` — screenshot generation
- `app/jobs/generate_preview_job.rb` — preview clip generation
- `app/models/video.rb` — `probed?`, `probe!`, `ffmpeg_input`
