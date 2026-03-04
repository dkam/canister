# Canister

Self-hosted video platform that aggregates media from multiple backends.

Canister is a reboot of [StashServer](https://github.com/stashapp/StashServer) by [stashapp](https://github.com/stashapp), originally built to organize and serve adult content. The codebase has been modernized and broadened to support all video types.

> The original project has since been rewritten in Go as [stashapp/stash](https://github.com/stashapp/stash).

## What It Does

- **Multi-backend aggregation** — local files, WebDAV, S3, Jellyfin, and Plex servers, all unified in one library
- **HLS streaming** — browser-based playback with adaptive bitrate
- **Web UI** — Turbo, Stimulus, Tailwind CSS
- **Background processing** — thumbnail generation, transcoding, sprite sheets, preview clips

## Stack

- Ruby 4.0.1, Rails 8.1.2
- SQLite3 (Solid Cache, Solid Queue, Solid Cable — no Redis)
- Tailwind CSS v4, Turbo, Stimulus, Propshaft, Importmap

## Setup

```bash
bundle install
```

Create `config/application.yml`:

```yaml
stash_directory: ''
stash_metadata_directory: ''
stash_cache_directory: ''
stash_downloads_directory: ''
```

```bash
rails s
```

The app runs on port 3000 by default.

## Docker

A `Dockerfile` and `docker-compose.yml` are provided. Libraries are mounted as volumes under `/videos/` (e.g. `/videos/movies`, `/videos/tv`). The app only sees container-side paths.

## NGINX

Use NGINX as a reverse proxy on port 4000. The app uses `X-Accel-Redirect` for efficient file streaming — NGINX serves the file directly from disk rather than proxying through Rails.

Example config:

```nginx
server {
    listen 4000;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }

    location /videos/ {
        internal;
        alias /path/to/your/videos/;
    }
}
```

## Rake Tasks

```bash
rails metadata:scan              # scan video directory, checksum files, generate thumbnails
rails metadata:import            # drop DB and reimport from metadata JSON
rails metadata:export            # export DB to metadata JSON
rails metadata:generate_sprites  # VTT sprite sheets for timeline scrubbing
rails metadata:generate_previews # MP4 preview clips
rails metadata:generate_transcodes  # transcode non-HTML5 formats
rails metadata:generate_all      # run all generate tasks
rails metadata:cleanup           # remove generated files for deleted videos
```

## Library Backends

| Backend | Status |
|---------|--------|
| Local filesystem | Working |
| WebDAV | Working |
| S3-compatible | Planned |
| Jellyfin (as source) | Planned |
| Plex (as source) | Planned |

## License

MIT. See [LICENSE](LICENSE).
