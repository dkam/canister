# Canister

Rails app for the Canister media organizer. Serves an HTML frontend using Turbo/Stimulus/Tailwind.

## Stack

- **Ruby**: 3.4.7
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

### Next steps

- Upgrade Ruby 3.4.7 → 4.0.1

### Known issues

- `rubyzip` uses pre-v3 API — update when convenient
- `params[:format] == :jpg` in `scenes_controller.rb:49` is a bug (string vs symbol comparison)
