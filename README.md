# Canister

A self-hosted video organizer and streaming server. Browse, tag, search, and stream your video library from any browser.

Originally forked from [StashServer](https://github.com/stashapp/StashServer) by [stashapp](https://github.com/stashapp) (since rewritten in Go as [stashapp/stash](https://github.com/stashapp/stash)). The codebase has been modernized — Rails 8, Ruby 4, Solid stack — and broadened to support all video types.

## Features

- Web UI for browsing, searching, and tagging videos (Turbo + Stimulus + Tailwind)
- HLS streaming with in-browser playback
- Background processing: thumbnails, sprite sheets, preview clips, transcoding
- Multiple library backends (local filesystem, WebDAV — more planned)
- SQLite-only — no Redis, no Postgres, no external services
- Metadata import/export (JSON)

## Requirements

| Dependency | Notes |
|---|---|
| **Ruby** | 4.0.1 |
| **ffmpeg** | Video processing, thumbnail generation, transcoding |
| **ImageMagick** | Image manipulation (sprite sheets, thumbnails) |
| **libvips** | Fast image processing (used via `ruby-vips`) |
| **Node.js** | Required by `tailwindcss-rails` for CSS builds |

All of these are installed automatically in the Docker image.

## Quick Start (Development)

```bash
git clone https://github.com/your-org/canister.git
cd canister
bundle install
```

Create the database and seed a default library:

```bash
bin/rails db:setup
```

This creates the SQLite databases in `storage/` and seeds a default "Local" library pointing at `/videos` (override with `VIDEO_PATH`).

Start the server:

```bash
bin/rails server
```

Open [http://localhost:3000](http://localhost:3000). Add videos to your library path, then scan:

```bash
bin/rails metadata:scan
```

## Docker

```bash
docker compose up
```

The default `docker-compose.yml`:

```yaml
services:
  web:
    build: .
    ports:
      - "3000:3000"
    volumes:
      - /videos:/videos              # your video library
      - /transcodes:/transcodes      # transcoded files
      - /storage:/app/storage        # SQLite databases + ActiveStorage
    environment:
      - RAILS_ENV=production
      - RAILS_LOG_TO_STDOUT=true
      - DEFAULT_LIBRARY_PATH=/videos
      - TRANSCODE_PATH=/transcodes
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/up"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 30s
```

Adjust the left side of each volume mount to match your host paths. The `storage/` volume is important — it holds the SQLite databases. Losing it means re-scanning your library.

A `.env.example` is provided as a reference for available environment variables.

## Configuration

### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `VIDEO_PATH` | `/videos` | Default library path (used by `db:seed`) |
| `TRANSCODE_PATH` | `./transcodes` | Directory for transcoded video files |
| `STASH_PATH` | `./metadata` | Metadata directory (screenshots, VTT, markers, JSON exports) |
| `RAILS_ENV` | `development` | Set to `production` for Docker/deployment |
| `RAILS_LOG_TO_STDOUT` | — | Enable for Docker (logs go to stdout instead of files) |
| `RAILS_MASTER_KEY` | — | Required in production if using encrypted credentials |
| `PORT` | `3000` | Puma listen port |
| `RAILS_MAX_THREADS` | `5` | Puma threads per worker |
| `WEB_CONCURRENCY` | `2` | Puma worker processes |

### Database

Zero-config. SQLite databases are auto-created in `storage/` on first run:

- `storage/development.sqlite3` — app data
- `storage/production.sqlite3` — app data (production)
- `storage/cache.sqlite3` — Solid Cache
- `storage/queue.sqlite3` — Solid Queue
- `storage/cable.sqlite3` — Solid Cable

No migrations to run manually — `db:setup` handles everything.

## NGINX (Optional)

NGINX as a reverse proxy enables `X-Accel-Redirect` — Rails tells NGINX which file to serve, and NGINX streams it directly from disk. This avoids tying up a Ruby process for large file transfers.

```nginx
server {
    listen 4000;

    # Proxy to Rails
    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # WebSocket support (Solid Cable / Turbo Streams)
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # X-Accel-Redirect: serve video files directly from disk
    location /videos/ {
        internal;
        alias /path/to/your/videos/;

        # Large file streaming
        sendfile on;
        tcp_nopush on;
        aio on;
        directio 512;
    }

    # X-Accel-Redirect: serve transcoded files
    location /transcodes/ {
        internal;
        alias /path/to/your/transcodes/;

        sendfile on;
        tcp_nopush on;
    }
}
```

Replace `/path/to/your/videos/` and `/path/to/your/transcodes/` with your actual paths. Without NGINX, Rails serves files directly — fine for development, but NGINX is recommended for production.

## Rake Tasks

```bash
bin/rails metadata:scan               # scan library, checksum files, generate thumbnails
bin/rails metadata:import             # drop DB and reimport from metadata JSON
bin/rails metadata:export             # export DB to metadata JSON
bin/rails metadata:generate_sprites   # VTT sprite sheets for timeline scrubbing
bin/rails metadata:generate_previews  # MP4 preview clips
bin/rails metadata:generate_transcodes  # transcode non-HTML5 formats
bin/rails metadata:generate_all       # run all generate tasks
bin/rails metadata:cleanup            # remove generated files for deleted videos
```

## Library Backends

| Backend | Status |
|---|---|
| Local filesystem | Working |
| WebDAV | Working |
| S3-compatible | Planned |
| Jellyfin (as source) | Planned |
| Plex (as source) | Planned |

See [docs/roadmap.md](docs/roadmap.md) for future plans.

## License

MIT — see [LICENSE](LICENSE).
