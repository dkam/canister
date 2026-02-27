# Canister

Rails API server for the Canister media organizer. Serves a GraphQL API and ActionCable subscriptions for a separate frontend.

## Stack

- **Ruby**: 3.4.7
- **Rails**: 8.1.2 (API-only, `config.api_only = true`)
- **Database**: SQLite3 (`db/development.sqlite3`, `db/test.sqlite3`)
- **API**: GraphQL (`/graphql`) + ActionCable (`/subscriptions`)
- **No asset pipeline** — Sprockets is commented out in `application.rb`
- **No views or helpers**

## Key Gems

- `graphql`, `graphql-errors` — GraphQL API
- `redis` — ActionCable adapter
- `kaminari` — pagination
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

- `app/graphql/` — schema, types, mutations, resolvers, functions
- `app/controllers/` — thin REST controllers (mostly media streaming/serving)
- `app/jobs/` — background jobs (scan, import, export, generate, clean)
- `app/models/concerns/` — `Filterable`, `Pageable`, `Sortable`, `Taggable`
- `lib/` — autoloaded and eager-loaded

## Related Projects (in `tmp/`)

- `tmp/StashFrontend` — the original React frontend (being replaced)
- `tmp/stash` — the Go rewrite of the original Stash app (reference/upstream)

## Upgrade Status

Rails upgrade **complete** — now on Rails 8.1.2 (`upgrade-rails-8.1-ruby-3.4.7` branch).

### Next steps

- Migrate to Solid Cache + Solid Queue + Solid Cable (replace Redis)
- Upgrade Ruby 3.4.7 → 4.0.1

### Known issues

- `rubyzip` uses pre-v3 API — update when convenient
- `params[:format] == :jpg` in `scenes_controller.rb:49` is a bug (string vs symbol comparison)
