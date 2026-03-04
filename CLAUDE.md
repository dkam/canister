# Canister

Rails app for the Canister media organizer. Serves an HTML frontend using Turbo/Stimulus/Tailwind.

## Stack

- **Ruby**: 4.0.1
- **Rails**: 8.1.2
- **Database**: SQLite3 (`db/development.sqlite3`, `db/test.sqlite3`)
- **Frontend**: Turbo, Stimulus, Tailwind CSS, Propshaft, Importmap

## Key Gems

- `solid_cache`, `solid_queue`, `solid_cable` — Solid stack (no Redis)
- `pagy` — pagination
- `scoped_search` — search
- `streamio-ffmpeg` — video processing
- `mechanize`, `selenium-webdriver` — scrapers
- `figaro` — config via `config/application.yml`

## Configuration

App settings live in `config/application.yml` (managed by Figaro, not committed):

```yaml
stash_directory: ''
stash_metadata_directory: ''
stash_cache_directory: ''
stash_downloads_directory: ''
```

## Development

```bash
bundle install
rails s           # runs on port 3000
```

Use NGINX as a reverse proxy on port 4000 (see README for config). The app uses `X-Accel-Redirect` for file streaming.

## Rake Tasks

```bash
rails metadata:scan              # scan stash dir, build DB, generate thumbnails
rails metadata:import            # drop DB and import from metadata dir
rails metadata:export            # export DB to JSON in metadata dir
rails metadata:generate_sprites  # VTT sprite sheets for scrubbing
rails metadata:generate_previews # MP4 preview clips
rails metadata:generate_transcodes
rails metadata:cleanup           # remove orphaned generated files
rails metadata:generate_all      # run all generate tasks
```

## App Structure

- `app/controllers/` — controllers (HTML views + media streaming/serving)
- `app/jobs/` — background jobs (scan, import, export, generate, clean)
- `app/models/concerns/` — `Filterable`, `Pageable`, `Sortable`, `Taggable`
- `lib/` — autoloaded and eager-loaded

## Related Projects (in `tmp/`)

- `tmp/StashFrontend` — the original React frontend (being replaced)
- `tmp/stash` — the Go rewrite of the original Stash app (reference/upstream)

## Upgrade Status

Rails upgrade **complete** — now on Rails 8.1.2.
Solid stack **complete** — Solid Cache, Solid Queue, Solid Cable in use (no Redis).
UUIDv7 **complete** — all primary key `id` columns use UUIDv7. Stored as 16-byte binary (`blob(16)` in SQLite), exposed as 25-char base36 strings (e.g. `"01jcqzx8h0000000000000000"`). Custom type registered in `lib/rails_ext/active_record_uuid_type.rb`; generation via `SecureRandom.uuid_v7`. No `primary_key` declarations needed in models.
HLS streaming **basic working** — HLS playback is functional.

### Known issues

- `rubyzip` uses pre-v3 API — update when convenient

## Roadmap

### Library Sources

`Library` model exists with `name`, `path`, `kind`, `read_only`, `default_video_kind`. `Scene` has `belongs_to :library`. No controller/UI or seed logic yet.

A default local library should be created at first run pointing to `/videos/`. In Docker, additional libraries are mounted as volumes under `/videos/` (e.g. `/videos/movies`, `/videos/tv`). The app only ever sees container-side paths.

Supported sources (read-only or read-write):

- **Local disk** — current implementation, single hardcoded path
- **HTTP directory** — static file server / Apache/Nginx directory listings
- **WebDAV** — read-write capable
- **S3** — object storage
- **Jellyfin** — media server integration (planned)
- **Plex** — media server integration (planned)
- **DLNA** — future/maybe

### Collections (Organisational Structure)

Videos can belong to one or more `Collection` nodes at any level of the hierarchy.

```
Collection (self-referential)
  - name
  - description
  - kind: franchise, series, season, playlist, channel, album, ...
  - parent_id (optional)

VideoCollection (join table)
  - video_id
  - collection_id
  - position (ordering within the collection)
```

- A video can belong to multiple collections (e.g., a season AND the series, or two different playlists)
- Position is scoped per collection, enabling separate release order vs. watch order via different collection memberships
- Collections are hierarchical but videos can attach at any level, not just leaves

### Domain Model Renames

- `Performer` → `Person` (model), `people` (table) — routes/controller already updated
- `Scene` → `Video` (model + table)
- `Studio` → `Creator` (tbd) — covers studios, YouTube channels, bands

### Video `kind` enum

Two values only: `:video` (default) and `:music_video`.

Music video is the one content type that's categorically distinct — different UI (artist/song vs cast/studio), different browse/filter behaviour. Everything else (movies, episodes, clips) is inferable from collection membership + duration and doesn't need explicit typing.

No STI — subclassing is overkill for a single enum field. No separate `Song` or `Album` models for now — music videos get optional `song_title` on the Video model; artist is covered by the existing `Person` association. Album-as-Collection breaks down because Collection groups Videos, not Songs. Defer if a real use case emerges.

### Bookmarks & Snippets (replaces SceneMarker)

`SceneMarker` is absorbed into `Video` via `parent_id` + timestamps. No separate model, no STI.

```
Video
  - parent_id (optional)       → source video
  - start_seconds (optional)
  - end_seconds (optional)
  - [file via ActiveStorage, optional]
```

States are implicit from the data:
- `parent_id` + no file = **bookmark** — a named, tagged point of interest
- `parent_id` + file = **snippet** — extracted clip, provenance preserved
- No `parent_id` = **standalone video**

Rules:
- One level deep only — a child Video cannot itself be a parent
- Multiple children can overlap (e.g. a 10s and a 30s snippet of the same moment are both valid)
- Promotion from bookmark → snippet just attaches a file; no class change, no record duplication
- ActiveStorage used for both generated clips and uploaded files — no distinction needed
- Bookmarks/snippets inherit people and collection membership from their parent — no need to duplicate associations

### Jellyfin API Compatibility

Implement enough of the Jellyfin REST API that existing Jellyfin clients (Infuse, mobile apps, Android TV, Roku) can connect to Canister as if it were a Jellyfin server. Core endpoints: auth, library browsing, item details, images, playback info, search, watch status. This is the primary strategy for device support — replaces DLNA.

### MCP Endpoint

Expose an MCP endpoint (`/mcp`) using Streamable HTTP transport so LLMs (Claude Code, Claude Desktop, etc.) can manage the library — renaming, tagging, categorising media. Bearer token auth, JSON-RPC protocol.

### Bonjour / mDNS Discovery

Zero-config discovery of the Canister server on the local network using `dnssd` gem and Avahi in Docker. Enables automatic server discovery by tvOS app and other clients.

### tvOS App

Native Apple TV app using TVML/TVMLKit — lightweight Swift shell with server-hosted JS/TVML templates. Paid app to support the open source project.

### Not Adding

- **yt-dlp** — media download functionality
- **Bittorrent** — torrent download functionality

### Detailed Notes

See `docs/goals.md` for detailed architecture notes and implementation plans (private, not committed).
